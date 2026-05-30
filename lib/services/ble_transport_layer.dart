// ── BleTransportLayer — VEXT BLE Scanning, Advertising & GATT Exchange ────────
//
// Responsibilities (Milestone 2 + 3):
//   • Scan for VEXT mesh nodes using the VEXT service UUID filter.
//   • Gate incoming advertisements by RSSI threshold.
//   • Parse advertisement service data into MeshPacket headers.
//   • Track peer count and expose it to BleStateNotifier.
//   • Implement adaptive duty cycling (idle / session / SOS modes).
//   [Milestone 3 additions]
//   • Advertise VEXT service UUID via Kotlin BleAdvertiser platform channel.
//   • Receive full MeshPackets via Kotlin VextGattServer (EventChannel).
//   • Send full MeshPackets to peers via GATT client (flutter_blue_plus).
//   • Start/stop Kotlin GATT server lifecycle.
//
// Platform channels (Kotlin ↔ Dart):
//   MethodChannel "com.example.vext/ble_advertiser"   → BLE peripheral advertising
//   MethodChannel "com.example.vext/gatt_server"      → GATT server lifecycle
//   EventChannel  "com.example.vext/gatt_packets"     → incoming GATT packet bytes
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/app_constants.dart';
import '../core/proto/mesh_packet.dart';

// ── Callback types ─────────────────────────────────────────────────────────────

/// Called when a full MeshPacket arrives (from advertisement header OR GATT write).
typedef PacketReceivedCallback = void Function(MeshPacket packet, int rssi);

/// Called whenever the count of visible VEXT peers changes.
typedef PeerCountChangedCallback = void Function(int count);

// ── Duty-cycle mode ────────────────────────────────────────────────────────────

/// Controls how aggressively BLE scanning runs.
///
/// idle       — 3% duty cycle (1 s scan / 30 s sleep). Conserves battery.
/// session    — 50% duty cycle (500 ms scan / 500 ms sleep). Active class.
/// sos        — Near-continuous (100 ms on / 100 ms off). Emergency relay.
enum ScanDutyMode { idle, session, sos }

// ── BleTransportLayer ─────────────────────────────────────────────────────────

class BleTransportLayer {
  BleTransportLayer();

  // ── Platform channels ──────────────────────────────────────────────────────

  static const _advertiserChannel =
      MethodChannel('com.example.vext/ble_advertiser');

  static const _gattServerChannel =
      MethodChannel('com.example.vext/gatt_server');

  static const _gattPacketsChannel =
      EventChannel('com.example.vext/gatt_packets');

  // ── BLE UUIDs ─────────────────────────────────────────────────────────────

  static final Guid _vextServiceUuid = Guid(AppConstants.bleServiceUuid);
  static final Guid _vextWriteCharUuid = Guid(AppConstants.bleCharacteristicUuid);

  // ── State ──────────────────────────────────────────────────────────────────

  bool _running = false;
  ScanDutyMode _dutyMode = ScanDutyMode.idle;

  /// device remoteId → last RSSI (in-memory "currently visible" peers)
  final Map<String, int> _peerRssi = {};

  /// device remoteId → BluetoothDevice (needed for GATT client connections)
  final Map<String, BluetoothDevice> _peerDevices = {};

  // ── Callbacks ─────────────────────────────────────────────────────────────

  PacketReceivedCallback? onPacketReceived;
  PeerCountChangedCallback? onPeerCountChanged;

  // ── Subscriptions / timers ────────────────────────────────────────────────

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<dynamic>? _gattPacketSub;
  Timer? _dutyCycleTimer;

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isRunning => _running;
  int get peerCount => _peerRssi.length;
  ScanDutyMode get dutyMode => _dutyMode;

  /// Start BLE scanning + advertising + GATT server with the given duty-cycle mode.
  /// Safe to call multiple times — subsequent calls update the duty mode only.
  Future<void> start({ScanDutyMode mode = ScanDutyMode.idle}) async {
    _dutyMode = mode;

    if (_running) {
      // Mode changed while running — restart duty cycle without re-starting GATT.
      _restartDutyCycle();
      return;
    }

    _running = true;

    // ── Start Kotlin GATT server ──────────────────────────────────────────
    // Errors are non-fatal — device may not support peripheral mode.
    try {
      await _gattServerChannel.invokeMethod<bool>('startServer');
    } catch (_) {
      // GATT server unavailable — app can still scan and receive via advertisement.
    }

    // ── Subscribe to incoming GATT packets ────────────────────────────────
    _gattPacketSub = _gattPacketsChannel
        .receiveBroadcastStream()
        .listen(_onGattPacketReceived, onError: (_) {});

    // ── Start BLE scanning ────────────────────────────────────────────────
    _adapterSub = FlutterBluePlus.adapterState.listen(_onAdapterState);
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);

    await _startScanOnce();
    _scheduleDutyCycle();
  }

  /// Stop all scanning, advertising, and GATT operations.
  Future<void> stop() async {
    _running = false;

    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;

    await _scanSub?.cancel();
    _scanSub = null;

    await _adapterSub?.cancel();
    _adapterSub = null;

    await _gattPacketSub?.cancel();
    _gattPacketSub = null;

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }

    // Stop Kotlin advertiser + GATT server — errors are non-fatal.
    try {
      await _advertiserChannel.invokeMethod<bool>('stopAdvertising');
    } catch (_) {}

    try {
      await _gattServerChannel.invokeMethod<bool>('stopServer');
    } catch (_) {}

    _peerRssi.clear();
    _peerDevices.clear();
    onPeerCountChanged?.call(0);
  }

  /// Switch duty-cycle mode (e.g. when a session starts or SOS is triggered).
  Future<void> setMode(ScanDutyMode mode) async {
    if (!_running) return;
    _dutyMode = mode;
    _restartDutyCycle();
  }

  // ── Advertising (wired to Kotlin BleAdvertiser) ───────────────────────────

  /// Advertise this node with the given packet's 18-byte header as payload.
  ///
  /// The Kotlin BleAdvertiser uses the VEXT service UUID so scanner's
  /// [withServices] filter will match. The 18-byte payload (type + ttl + uuid)
  /// is included as manufacturer data in the scan response.
  ///
  /// Called by:
  ///   • AttendanceService — to announce an active session (Milestone 4).
  ///   • MeshService — to keep the node discoverable (Milestone 3).
  Future<void> advertisePacket(MeshPacket packet) async {
    try {
      final payload = packet.toAdvertisementBytes();
      await _advertiserChannel.invokeMethod<bool>(
        'startAdvertising',
        {'payload': payload.toList()},
      );
    } catch (_) {
      // Advertising not supported or permission denied — degrade gracefully.
    }
  }

  /// Stop BLE advertising (e.g. when session ends or SOS is resolved).
  Future<void> stopAdvertising() async {
    try {
      await _advertiserChannel.invokeMethod<bool>('stopAdvertising');
    } catch (_) {}
  }

  // ── GATT client — send packets to peers ───────────────────────────────────

  /// Send [packetBytes] to a single peer via GATT write.
  ///
  /// Connects → discovers services → finds VEXT write characteristic
  /// → writes bytes → disconnects. Times out after 6 s total.
  ///
  /// Errors are silently swallowed — a failed write means the peer moved
  /// out of range; MeshService handles the retry/TTL policy.
  Future<void> sendPacketToPeer(
    BluetoothDevice device,
    List<int> packetBytes,
  ) async {
    try {
      await device.connect(
        timeout: const Duration(seconds: 5),
        autoConnect: false,
      );

      final services = await device.discoverServices();

      BluetoothService? vextService;
      for (final s in services) {
        if (s.serviceUuid == _vextServiceUuid) {
          vextService = s;
          break;
        }
      }
      if (vextService == null) {
        await device.disconnect();
        return;
      }

      BluetoothCharacteristic? writeChar;
      for (final c in vextService.characteristics) {
        if (c.characteristicUuid == _vextWriteCharUuid) {
          writeChar = c;
          break;
        }
      }
      if (writeChar == null) {
        await device.disconnect();
        return;
      }

      await writeChar.write(packetBytes, withoutResponse: true);
      await device.disconnect();
    } catch (_) {
      // Disconnect on any error so we don't leave orphan connections.
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  /// Broadcast [packetBytes] to ALL currently known peers via GATT.
  ///
  /// Fires all GATT writes concurrently (fire-and-forget) so SOS is not
  /// serialised through each peer. Individual GATT errors are silently ignored.
  ///
  /// Called by MeshService when relaying a packet.
  void broadcastPacket(List<int> packetBytes) {
    final devices = List<BluetoothDevice>.from(_peerDevices.values);
    for (final device in devices) {
      sendPacketToPeer(device, packetBytes).ignore();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() => stop();

  // ── Private — Scan result processing ─────────────────────────────────────

  void _onScanResults(List<ScanResult> results) {
    final prevCount = _peerRssi.length;

    for (final result in results) {
      final rssi = result.rssi;

      // Gate by minimum signal strength.
      if (rssi < AppConstants.rssiMeshMinimum) continue;

      final deviceId = result.device.remoteId.str;
      _peerRssi[deviceId] = rssi;
      _peerDevices[deviceId] = result.device; // keep for GATT client

      // Parse advertisement service data for the 18-byte MeshPacket header.
      final serviceData = result.advertisementData.serviceData;
      final vextData = serviceData[_vextServiceUuid];

      if (vextData != null && vextData.isNotEmpty) {
        _processAdvertisementData(Uint8List.fromList(vextData), rssi);
      }
    }

    if (_peerRssi.length != prevCount) {
      onPeerCountChanged?.call(_peerRssi.length);
    }
  }

  /// Process an 18-byte advertisement header from the scan result service data.
  void _processAdvertisementData(Uint8List data, int rssi) {
    final packet = MeshPacket.fromAdvertisementBytes(data);
    if (packet == null) return;
    // senderUid is '' for advertisement-only packets — MeshService uses this
    // to distinguish header-only packets (dedup/discovery) from full GATT packets.
    onPacketReceived?.call(packet, rssi);
  }

  // ── Private — GATT incoming packets ──────────────────────────────────────

  /// Called by the EventChannel listener when the Kotlin GATT server receives
  /// a write from a peer GATT client. [data] is a List<int> of raw packet bytes.
  void _onGattPacketReceived(dynamic data) {
    if (data is! List) return;
    final bytes = Uint8List.fromList(data.cast<int>());
    final packet = MeshPacket.fromBytes(bytes);
    if (packet == null) return;
    // rssi = 0 for GATT packets (RSSI not available after connection handshake).
    onPacketReceived?.call(packet, 0);
  }

  // ── Private — Scanning mechanics ─────────────────────────────────────────

  Future<void> _startScanOnce() async {
    try {
      if (FlutterBluePlus.isScanningNow) return;
      await FlutterBluePlus.startScan(
        withServices: [_vextServiceUuid],
        timeout: _scanDuration(),
      );
    } catch (_) {
      // BLE not available, permissions denied, etc. — fail silently.
    }
  }

  void _scheduleDutyCycle() {
    _dutyCycleTimer?.cancel();
    final activeDuration = _scanDuration();
    final sleepDuration = _sleepDuration();

    _dutyCycleTimer = Timer(activeDuration + sleepDuration, () {
      if (!_running) return;
      _startScanOnce();
      _scheduleDutyCycle();
    });
  }

  void _restartDutyCycle() {
    _dutyCycleTimer?.cancel();
    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan().then((_) {
        _startScanOnce();
        _scheduleDutyCycle();
      });
    } else {
      _startScanOnce();
      _scheduleDutyCycle();
    }
  }

  // ── Private — Adapter state ───────────────────────────────────────────────

  void _onAdapterState(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.on && _running) {
      _startScanOnce();
    } else if (state != BluetoothAdapterState.on) {
      _peerRssi.clear();
      _peerDevices.clear();
      onPeerCountChanged?.call(0);
    }
  }

  // ── Private — Duty-cycle durations ───────────────────────────────────────

  Duration _scanDuration() => switch (_dutyMode) {
        ScanDutyMode.idle =>
          const Duration(milliseconds: AppConstants.dutyCycleActiveMsIdle),
        ScanDutyMode.session =>
          const Duration(milliseconds: AppConstants.dutyCycleActiveMsSession),
        ScanDutyMode.sos =>
          const Duration(milliseconds: AppConstants.dutyCycleActiveMsSos),
      };

  Duration _sleepDuration() => switch (_dutyMode) {
        ScanDutyMode.idle =>
          const Duration(milliseconds: AppConstants.dutyCycleSleepMsIdle),
        ScanDutyMode.session =>
          const Duration(milliseconds: AppConstants.dutyCycleSleepMsSession),
        ScanDutyMode.sos =>
          const Duration(milliseconds: AppConstants.dutyCycleSleepMsSos),
      };
}
