// ── BleTransportLayer — VEXT BLE Scanning, Advertising & GATT Exchange ────────
//
// Responsibilities (Milestone 2 + 3):
//   • Scan for VEXT mesh nodes.
//   • Gate incoming scan results by RSSI threshold.
//   • Identify VEXT peers by checking advertisement serviceUuids.
//   • Track peer count and expose it to BleStateNotifier.
//   • Implement adaptive duty cycling (idle / session / SOS modes).
//   [Milestone 3]
//   • Request BLUETOOTH_ADVERTISE at runtime before advertising.
//   • Advertise VEXT service UUID via Kotlin BleAdvertiser platform channel.
//   • Expose advertising success/failure via onAdvertisingStateChanged callback.
//   • Receive full MeshPackets via Kotlin VextGattServer (EventChannel).
//   • Send full MeshPackets to peers via GATT client (flutter_blue_plus).
//
// ── Design decisions (post M3 debugging) ──────────────────────────────────────
//
// 1. NO withServices scan filter.
//    On Samsung Galaxy S25 Ultra (One UI 7 / Android 14), the BLE stack
//    silently drops scan results when a 128-bit custom service UUID filter is
//    applied, even when the peer IS advertising that UUID. Removing the filter
//    and checking serviceUuids manually in _onScanResults() is far more reliable
//    across all tested devices. Battery impact is negligible in a classroom range.
//
// 2. VEXT device detection via serviceUuids, NOT serviceData.
//    BleAdvertiser.kt calls addServiceUuid() → populates
//    result.advertisementData.serviceUuids. It does NOT call addServiceData(),
//    so serviceData is always empty for VEXT heartbeat advertisements.
//
// 3. Explicit BLUETOOTH_ADVERTISE permission request.
//    flutter_blue_plus handles BLUETOOTH_SCAN and BLUETOOTH_CONNECT internally.
//    BLUETOOTH_ADVERTISE is used by our custom Kotlin BleAdvertiser and must be
//    requested separately via permission_handler before advertising starts.
//    Failure is now reported via onAdvertisingStateChanged instead of being
//    silently swallowed — the UI shows a clear warning when advertising is off.
//
// Platform channels (Kotlin ↔ Dart):
//   MethodChannel "com.example.vext/ble_advertiser"  → BLE peripheral advertising
//   MethodChannel "com.example.vext/gatt_server"     → GATT server lifecycle
//   EventChannel  "com.example.vext/gatt_packets"    → incoming GATT packet bytes
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_constants.dart';
import '../core/proto/mesh_packet.dart';

// ── Callback types ─────────────────────────────────────────────────────────────

/// Called when a full MeshPacket arrives (advertisement header OR GATT write).
typedef PacketReceivedCallback = void Function(MeshPacket packet, int rssi);

/// Called whenever the count of visible VEXT peers changes.
typedef PeerCountChangedCallback = void Function(int count);

/// Called when advertising state changes.
/// [isAdvertising] = true when the Kotlin BleAdvertiser started successfully.
/// [error] = human-readable reason when advertising failed (empty on success).
typedef AdvertisingStateChangedCallback = void Function(
    bool isAdvertising, String error);

// ── Duty-cycle mode ────────────────────────────────────────────────────────────

/// Controls how aggressively BLE scanning runs.
///
/// idle    — 3% duty cycle (1 s scan / 30 s sleep). Conserves battery.
/// session — 50% duty cycle (500 ms scan / 500 ms sleep). Active class.
/// sos     — Near-continuous (100 ms on / 100 ms off). Emergency relay.
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

  // ── VEXT service UUID string for manual comparison (lowercase, normalised) ─
  // Used in _isVextDevice() to compare against advertisementData.serviceUuids.
  static final String _vextUuidNormalised =
      AppConstants.bleServiceUuid.toLowerCase();

  // ── State ──────────────────────────────────────────────────────────────────

  bool _running = false;
  ScanDutyMode _dutyMode = ScanDutyMode.idle;

  /// device remoteId → last RSSI (currently visible VEXT peers)
  final Map<String, int> _peerRssi = {};

  /// device remoteId → BluetoothDevice (for GATT client writes)
  final Map<String, BluetoothDevice> _peerDevices = {};

  // ── Callbacks ─────────────────────────────────────────────────────────────

  PacketReceivedCallback? onPacketReceived;
  PeerCountChangedCallback? onPeerCountChanged;

  /// Fired immediately after every advertising start attempt.
  /// isAdvertising=true → Kotlin BleAdvertiser confirmed started.
  /// isAdvertising=false → error string explains why.
  AdvertisingStateChangedCallback? onAdvertisingStateChanged;

  // ── Subscriptions / timers ────────────────────────────────────────────────

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<dynamic>? _gattPacketSub;
  Timer? _dutyCycleTimer;

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isRunning => _running;
  int get peerCount => _peerRssi.length;
  ScanDutyMode get dutyMode => _dutyMode;

  /// Start BLE scanning + advertising + GATT server.
  ///
  /// Safe to call multiple times — subsequent calls change the duty mode only.
  /// Requests BLUETOOTH_ADVERTISE permission before advertising. If denied, the
  /// app continues in scan-only mode and [onAdvertisingStateChanged] fires with
  /// an error message so the UI can prompt the user to fix the permission.
  Future<void> start({ScanDutyMode mode = ScanDutyMode.idle}) async {
    _dutyMode = mode;

    if (_running) {
      // Mode changed while already running — update duty cycle only.
      _restartDutyCycle();
      return;
    }

    _running = true;

    // ── Request BLE permissions ───────────────────────────────────────────
    // flutter_blue_plus handles BLUETOOTH_SCAN and BLUETOOTH_CONNECT internally.
    // We must explicitly request BLUETOOTH_ADVERTISE before calling our native
    // BleAdvertiser, and request location permissions required for BLE scanning.
    await _requestBlePermissions();

    // ── Start Kotlin GATT server ──────────────────────────────────────────
    // Non-fatal — some devices don't support peripheral GATT server mode.
    try {
      await _gattServerChannel.invokeMethod<bool>('startServer');
      debugPrint('[BLE] GATT server started');
    } catch (e) {
      debugPrint('[BLE] GATT server unavailable: $e');
    }

    // ── Subscribe to incoming GATT packets ────────────────────────────────
    _gattPacketSub = _gattPacketsChannel
        .receiveBroadcastStream()
        .listen(_onGattPacketReceived, onError: (_) {});

    // ── Start BLE advertising ─────────────────────────────────────────────
    // Advertise the VEXT service UUID so scanning peers can discover this node.
    // Result is reported via onAdvertisingStateChanged — NOT silently swallowed.
    await _startHeartbeat();

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

  /// Switch duty-cycle mode at runtime (e.g. when a class session starts).
  Future<void> setMode(ScanDutyMode mode) async {
    if (!_running) return;
    _dutyMode = mode;
    _restartDutyCycle();
  }

  // ── Advertising ───────────────────────────────────────────────────────────

  /// Advertise this node with the packet's 18-byte header as scan-response payload.
  ///
  /// Called by AttendanceService to announce an active session (Milestone 4).
  /// Errors are silently handled — advertising failures are reported via
  /// [onAdvertisingStateChanged] in [_startHeartbeat]; no separate callback here.
  Future<void> advertisePacket(MeshPacket packet) async {
    try {
      final payload = packet.toAdvertisementBytes();
      await _advertiserChannel.invokeMethod<bool>(
        'startAdvertising',
        {'payload': payload.toList()},
      );
    } catch (e) {
      debugPrint('[BLE] advertisePacket failed: $e');
    }
  }

  /// Stop BLE advertising.
  Future<void> stopAdvertising() async {
    try {
      await _advertiserChannel.invokeMethod<bool>('stopAdvertising');
    } catch (_) {}
  }

  // ── GATT client — send packets to peers ───────────────────────────────────

  /// Send [packetBytes] to a single peer via GATT write.
  ///
  /// Connect → discover services → find VEXT write characteristic → write → disconnect.
  /// All errors are silently ignored — a failed write means the peer moved out of
  /// range; MeshService / TTL policy handles retries.
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
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  /// Broadcast [packetBytes] to ALL currently known peers via GATT concurrently.
  void broadcastPacket(List<int> packetBytes) {
    final devices = List<BluetoothDevice>.from(_peerDevices.values);
    for (final device in devices) {
      sendPacketToPeer(device, packetBytes).ignore();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() => stop();

  // ── Private — Permission request ──────────────────────────────────────────

  /// Request all BLE-related runtime permissions before starting BLE operations.
  ///
  /// flutter_blue_plus handles BLUETOOTH_SCAN / BLUETOOTH_CONNECT internally when
  /// startScan() / connect() are called. We must request BLUETOOTH_ADVERTISE
  /// separately because our custom Kotlin BleAdvertiser uses it and the system
  /// dialog is never triggered by flutter_blue_plus.
  ///
  /// Location permission is required for BLE scanning on all Android versions.
  /// We request locationWhenInUse; the manifest also declares BACKGROUND_LOCATION
  /// for future foreground-service scanning (Milestone 7).
  Future<void> _requestBlePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    for (final entry in statuses.entries) {
      if (entry.value.isDenied || entry.value.isPermanentlyDenied) {
        debugPrint('[BLE] Permission ${entry.key} — ${entry.value}');
      }
    }
  }

  // ── Private — Heartbeat advertising ──────────────────────────────────────

  /// Advertise the VEXT service UUID so peer scanners can discover this node.
  ///
  /// Reports success/failure via [onAdvertisingStateChanged].
  /// A failed advertising start is a WARNING (not fatal) — the device continues
  /// in scan-only mode, but peer discovery will only be one-directional until
  /// the permission is fixed.
  Future<void> _startHeartbeat() async {
    try {
      await _advertiserChannel.invokeMethod<bool>(
        'startAdvertising',
        {'payload': <int>[]}, // empty = service UUID only in primary advertisement
      );
      debugPrint('[BLE] Advertising started — VEXT service UUID visible to peers');
      onAdvertisingStateChanged?.call(true, '');
    } on PlatformException catch (e) {
      // Known error codes from BleAdvertiser.kt:
      //   PERMISSION_DENIED   — BLUETOOTH_ADVERTISE not granted
      //   ADVERTISE_FAILED    — hardware error (too many advertisers, unsupported)
      //   BLE_UNAVAILABLE     — device has no BLE peripheral hardware
      final msg = _humanReadableAdvertiseError(e);
      debugPrint('[BLE] Advertising FAILED: ${e.code} — ${e.message}');
      onAdvertisingStateChanged?.call(false, msg);
    } catch (e) {
      debugPrint('[BLE] Advertising FAILED (unexpected): $e');
      onAdvertisingStateChanged?.call(false, e.toString());
    }
  }

  String _humanReadableAdvertiseError(PlatformException e) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return 'BLUETOOTH_ADVERTISE permission not granted. '
            'Go to Settings → Apps → VEXT → Permissions → Nearby devices → Allow, '
            'then restart the app.';
      case 'BLE_UNAVAILABLE':
        return 'This device does not support BLE advertising (scan-only mode).';
      case 'ADVERTISE_FAILED':
        final detail = e.message ?? '';
        if (detail.contains('Too many')) {
          return 'BLE advertising slot busy — another app is advertising. '
              'Close other BLE apps and restart VEXT.';
        }
        if (detail.contains('unsupported')) {
          return 'BLE advertising not supported on this device (scan-only mode).';
        }
        return 'BLE advertising failed: $detail';
      default:
        return e.message ?? e.code;
    }
  }

  // ── Private — Scan result processing ─────────────────────────────────────

  /// Process incoming scan results and update the peer map.
  ///
  /// We do NOT use a withServices filter on startScan() because it is unreliable
  /// on Samsung One UI 7 / Android 14 — the OS-level filter silently drops
  /// valid VEXT scan results for 128-bit custom UUIDs. Instead, every scan result
  /// passes through this handler and we identify VEXT peers by checking
  /// result.advertisementData.serviceUuids (populated from the advertisement's
  /// "Service UUID List" AD type — exactly what BleAdvertiser.addServiceUuid() sets).
  void _onScanResults(List<ScanResult> results) {
    final prevCount = _peerRssi.length;

    for (final result in results) {
      final rssi = result.rssi;

      // Gate by minimum signal strength. Discard noise / distant devices.
      if (rssi < AppConstants.rssiMeshMinimum) continue;

      // Only accept VEXT mesh nodes. Non-VEXT devices (headphones, smartwatches, etc.)
      // are filtered here so they never pollute _peerDevices.
      if (!_isVextDevice(result)) continue;

      final deviceId = result.device.remoteId.str;
      _peerRssi[deviceId] = rssi;
      _peerDevices[deviceId] = result.device; // retained for GATT client writes

      // If the peer included 18-byte MeshPacket header data in the scan response
      // manufacturer data, parse it. This is optional — full packets arrive
      // via GATT. For heartbeat advertisements (empty payload), this is a no-op.
      _tryParseManufacturerData(result, rssi);
    }

    if (_peerRssi.length != prevCount) {
      onPeerCountChanged?.call(_peerRssi.length);
    }
  }

  /// Returns true if [result] is a VEXT VigilantMesh node.
  ///
  /// Checks result.advertisementData.serviceUuids for the VEXT service UUID.
  /// This is the list populated by BleAdvertiser.addServiceUuid() on the peer.
  ///
  /// Comparison is case-insensitive because flutter_blue_plus may normalise
  /// UUIDs to lowercase while the Kotlin side uses uppercase.
  bool _isVextDevice(ScanResult result) {
    final uuids = result.advertisementData.serviceUuids;
    for (final guid in uuids) {
      if (guid.str.toLowerCase() == _vextUuidNormalised) {
        return true;
      }
    }
    return false;
  }

  /// Attempt to parse an 18-byte MeshPacket advertisement header from the
  /// scan result's manufacturer data (set by BleAdvertiser when a full
  /// attendance or mesh packet is being advertised).
  ///
  /// Heartbeat advertisements (empty payload from _startHeartbeat) have no
  /// manufacturer data — this is a no-op in the normal case.
  void _tryParseManufacturerData(ScanResult result, int rssi) {
    // Manufacturer data map: manufacturerId (int) → bytes
    final mfr = result.advertisementData.manufacturerData;
    if (mfr.isEmpty) return;

    // BleAdvertiser uses VEXT_MANUFACTURER_ID = 0xFFFE
    const vextManufacturerId = 0xFFFE;
    final data = mfr[vextManufacturerId];
    if (data == null || data.isEmpty) return;

    // The 18-byte advertisement header: type(1) + ttl(1) + uuid(16)
    if (data.length < 18) return;

    _processAdvertisementData(Uint8List.fromList(data), rssi);
  }

  /// Parse an 18-byte advertisement header into a MeshPacket and forward it.
  void _processAdvertisementData(Uint8List data, int rssi) {
    final packet = MeshPacket.fromAdvertisementBytes(data);
    if (packet == null) return;
    onPacketReceived?.call(packet, rssi);
  }

  // ── Private — GATT incoming packets ──────────────────────────────────────

  /// Called by the EventChannel when Kotlin GATT server receives a write from a peer.
  void _onGattPacketReceived(dynamic data) {
    if (data is! List) return;
    final bytes = Uint8List.fromList(data.cast<int>());
    final packet = MeshPacket.fromBytes(bytes);
    if (packet == null) return;
    onPacketReceived?.call(packet, 0); // rssi = 0 — not available post-connection
  }

  // ── Private — Scanning mechanics ─────────────────────────────────────────

  Future<void> _startScanOnce() async {
    try {
      if (FlutterBluePlus.isScanningNow) return;

      // NO withServices filter — see design note at top of file.
      // All BLE devices in range are scanned; _onScanResults() filters to VEXT only.
      await FlutterBluePlus.startScan(
        timeout: _scanDuration(),
      );
    } catch (e) {
      debugPrint('[BLE] startScan failed: $e');
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
