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
//   MethodChannel "com.vext.vext_app/ble_advertiser"  → BLE peripheral advertising
//   MethodChannel "com.vext.vext_app/gatt_server"     → GATT server lifecycle
//   EventChannel  "com.vext.vext_app/gatt_packets"    → incoming GATT packet bytes
//   MethodChannel "com.vext.vext_app/wake_lock"       → PARTIAL_WAKE_LOCK (Fix 1A)
//   MethodChannel "com.vext.vext_app/alarm_manager"   → Doze alarm scheduling (Fix 1B)
//   EventChannel  "com.vext.vext_app/alarm_events"    → Doze alarm fired events (Fix 1B)
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
      MethodChannel('com.vext.vext_app/ble_advertiser');

  static const _gattServerChannel =
      MethodChannel('com.vext.vext_app/gatt_server');

  static const _gattPacketsChannel =
      EventChannel('com.vext.vext_app/gatt_packets');

  /// WakeLock channel — keeps the CPU alive while BLE scanning runs.
  /// 'acquireWakeLock' / 'releaseWakeLock' are handled by MainActivity.kt.
  static const _wakeLockChannel =
      MethodChannel('com.vext.vext_app/wake_lock');

  /// AlarmManager channel — schedules a one-shot setExactAndAllowWhileIdle
  /// alarm. Fired even in deep Doze; rescheduled from Dart after each receipt.
  static const _alarmManagerChannel =
      MethodChannel('com.vext.vext_app/alarm_manager');

  /// Receives "scanRestart" strings from VextAlarmReceiver when the Doze
  /// alarm fires. BleTransportLayer calls _restartDutyCycle() on each event
  /// and immediately reschedules the next alarm (Fix 1B).
  static const _alarmEventsChannel =
      EventChannel('com.vext.vext_app/alarm_events');

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

  /// Number of GATT client operations currently in-flight.
  /// Capped at [AppConstants.maxConcurrentGattConnections] to prevent BLE
  /// radio exhaustion. Incremented at the start of sendPacketToPeer(),
  /// decremented in the finally block (always, even on error/timeout).
  int _activeGattConnections = 0;

  /// device remoteId → last RSSI (currently visible VEXT peers)
  final Map<String, int> _peerRssi = {};

  /// device remoteId → BluetoothDevice (for GATT client writes)
  final Map<String, BluetoothDevice> _peerDevices = {};

  /// device remoteId → time of last scan result — used for stale-peer eviction.
  /// Peers not seen for 60 s are removed from _peerRssi and _peerDevices so
  /// broadcastPacket() does not try to GATT-connect to out-of-range devices.
  final Map<String, DateTime> _peerLastSeen = {};

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
  /// Receives Doze-alarm events from VextAlarmReceiver (Fix 1B).
  StreamSubscription<dynamic>? _alarmEventSub;
  Timer? _dutyCycleTimer;
  Timer? _evictionTimer;

  // ── Retry queue (Fix 2C) ──────────────────────────────────────────────────
  // Packets whose broadcastPacket() call reached all peers successfully on 0
  // devices (all GATT slots busy, or no peers present) are queued here and
  // retried every [_retryIntervalMs] ms up to [_retryMaxAgeMs] ms.
  // Limited to [_retryQueueMaxSize] to bound memory.
  static const _retryIntervalMs = 3000;
  static const _retryMaxAgeMs   = 30000; // 30 s — covers 15 SOS re-broadcast cycles
  static const _retryQueueMaxSize = 8;
  final _retryQueue = <({List<int> bytes, DateTime expiresAt})>[];
  Timer? _retryTimer;

  // ── Health watchdog (Fix 1C) ──────────────────────────────────────────────
  // Periodically checks whether the duty-cycle timer is still alive. If it
  // has died silently (e.g., an uncaught exception in the timer callback in a
  // release build), the watchdog restarts it. Fires every 2 minutes — frequent
  // enough to recover before a user notices, infrequent enough to have zero
  // battery impact.
  Timer? _watchdogTimer;
  DateTime? _lastScanActivityTime; // updated on every scan callback (empty or not)

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
      // Mode changed while already running — update duty cycle AND reschedule
      // the Doze alarm at the new mode's interval. Without the reschedule, the
      // old alarm (e.g. 1 s for session mode) fires immediately after switching
      // to idle (31 s cycle), causing a spurious duty-cycle restart.
      _restartDutyCycle();
      _scheduleDozeAlarm().ignore();
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

    // Evict peers not seen for 60 s every 30 s to keep broadcastPacket() lean.
    _evictionTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _evictStalePeers(),
    );

    // Acquire a PARTIAL_WAKE_LOCK so Android does not sleep the CPU between
    // duty-cycle timer firings. Without this, Dart timers stall in Doze mode
    // and scanning stops silently whenever the screen turns off.
    // Non-fatal — some emulators and non-Android targets don't have this channel.
    try {
      await _wakeLockChannel.invokeMethod<bool>('acquireWakeLock');
      debugPrint('[BLE] WakeLock acquired');
    } catch (e) {
      debugPrint('[BLE] WakeLock unavailable: $e');
    }

    // Subscribe to Doze alarm events from VextAlarmReceiver (Fix 1B).
    // When deep Doze suspends the Dart event loop and stalls the duty-cycle
    // timer, the AlarmManager fires setExactAndAllowWhileIdle which wakes the
    // device and calls back here — we restart the duty cycle immediately.
    _alarmEventSub = _alarmEventsChannel.receiveBroadcastStream().listen(
      _onDozeAlarmEvent,
      onError: (e) => debugPrint('[BLE] alarmEvents error: $e'),
    );
    // Schedule the initial Doze alarm. Interval = one full duty cycle
    // (active + sleep) so it only fires if the normal Dart timer has stalled.
    await _scheduleDozeAlarm();

    // ── GATT retry timer (Fix 2C) ─────────────────────────────────────────
    // Fires every 3 s to resend packets that previously had no available GATT
    // connections. Complements the re-broadcast timers in SosService and
    // AttendanceService — covers the window between broadcast cycles.
    _retryTimer = Timer.periodic(
      const Duration(milliseconds: _retryIntervalMs),
      (_) => _processRetryQueue(),
    );

    // ── Health watchdog (Fix 1C) ──────────────────────────────────────────
    // Every 2 minutes, verify the duty-cycle timer is still ticking.
    // If it died silently (e.g. Doze killed the Dart VM timer callbacks even
    // with the WakeLock), restart the duty cycle immediately.
    _watchdogTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkBleHealth(),
    );
  }

  /// Stop all scanning, advertising, and GATT operations.
  Future<void> stop() async {
    _running = false;

    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;

    _evictionTimer?.cancel();
    _evictionTimer = null;

    _retryTimer?.cancel();
    _retryTimer = null;
    _retryQueue.clear();

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    await _scanSub?.cancel();
    _scanSub = null;

    await _adapterSub?.cancel();
    _adapterSub = null;

    await _gattPacketSub?.cancel();
    _gattPacketSub = null;

    await _alarmEventSub?.cancel();
    _alarmEventSub = null;
    await _cancelDozeAlarm();

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }

    try {
      await _advertiserChannel.invokeMethod<bool>('stopAdvertising');
    } catch (_) {}

    try {
      await _gattServerChannel.invokeMethod<bool>('stopServer');
    } catch (_) {}

    // Release the WakeLock — BLE is off, no need to keep the CPU awake.
    try {
      await _wakeLockChannel.invokeMethod<bool>('releaseWakeLock');
      debugPrint('[BLE] WakeLock released');
    } catch (_) {}

    _peerRssi.clear();
    _peerDevices.clear();
    _peerLastSeen.clear();
    // Do NOT hard-reset _activeGattConnections here. In-flight sendPacketToPeer
    // calls decrement it in their finally blocks. A hard reset to 0 races with
    // those decrements and makes the counter go negative, allowing more than
    // maxConcurrentGattConnections on the next start() call.
    // The counter will reach 0 naturally as in-flight ops complete.
    // New ops are blocked by the !_running guard in sendPacketToPeer.
    onPeerCountChanged?.call(0);
  }

  /// Switch duty-cycle mode at runtime (e.g. when a class session starts).
  Future<void> setMode(ScanDutyMode mode) async {
    if (!_running) return;
    _dutyMode = mode;
    _restartDutyCycle();
    // Reschedule Doze alarm at the new mode's interval so it matches the
    // new duty cycle. Without this, the alarm keeps the old interval until
    // it next fires and self-corrects — causing one spurious restart.
    _scheduleDozeAlarm().ignore();
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

  /// Send [packetBytes] to a single peer via GATT write, with up to 3 attempts.
  ///
  /// Returns `true` on success, `false` if all 3 attempts failed or the
  /// concurrency cap was already reached. The boolean result is used by
  /// [broadcastPacket] to decide whether to enqueue for retry (Fix 2C).
  ///
  /// Connect → MTU negotiation → discover services → write → disconnect.
  /// Backoff: 100 ms after attempt 1, 200 ms after attempt 2.
  ///
  /// [requireAck] — when true, the GATT write uses ATT Write Request
  ///   (withoutResponse: false). The BLE controller blocks until the peer
  ///   sends an ATT Attribute Protocol confirmation, guaranteeing the peer's
  ///   radio received the packet. Use for originated SOS and attendance packets
  ///   where delivery proof matters more than raw throughput.
  ///
  ///   When false (default), the write uses ATT Write Command
  ///   (withoutResponse: true). The call returns as soon as the local BLE
  ///   radio accepts the packet — no delivery confirmation from the peer.
  ///   Use for relay packets where throughput and low latency beat guarantee.
  ///   False is deliberately the default so existing relay call sites need no changes.
  Future<bool> sendPacketToPeer(
    BluetoothDevice device,
    List<int> packetBytes, {
    bool requireAck = false,
  }) async {
    // Reject new GATT operations when BLE is stopping. Without this guard,
    // stop() clears peer maps but in-flight ops still complete and decrement
    // _activeGattConnections — safe. But new ops started AFTER stop() was
    // called (e.g. from the retry queue firing concurrently) would increment
    // the counter and never be paired with a peer, leaving it permanently high.
    if (!_running) return false;

    // Guard: drop the send if we are already at the concurrent GATT limit.
    if (_activeGattConnections >= AppConstants.maxConcurrentGattConnections) {
      return false;
    }
    _activeGattConnections++;

    try {
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          await device.connect(
            timeout: const Duration(seconds: 5),
            autoConnect: false,
          );

          // Request maximum MTU before service discovery. Default ATT MTU is
          // 23 bytes (20 bytes payload). A MeshPacket with content easily exceeds
          // this. Requesting 512 causes Android to negotiate the largest MTU both
          // ends support (typically 247 or 512 on modern devices), so the full
          // packet is delivered in a single write operation instead of fragments.
          // Errors here are non-fatal — we continue with the default MTU.
          try {
            await device.requestMtu(512);
          } catch (_) {}

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
            // VEXT service gone — peer likely rebooted mid-session. Return false
            // but don't retry (the peer needs to re-advertise first).
            return false;
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
            return false; // Characteristic gone — no point retrying.
          }

          // requireAck=true  → ATT Write Request: peer sends confirmation.
          //   "return true" means the peer's BLE controller acknowledged receipt.
          // requireAck=false → ATT Write Command: fire-and-forget.
          //   "return true" means our local radio queued the packet.
          await writeChar.write(packetBytes, withoutResponse: !requireAck);
          await device.disconnect();
          return true; // ── Success ──
        } catch (_) {
          try { await device.disconnect(); } catch (_) {}
          if (attempt < 2) {
            // Backoff: 100ms after attempt 0, 200ms after attempt 1.
            await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
          }
        }
      }
      return false; // All 3 attempts failed.
    } finally {
      // Always decrement — even on early return or exception.
      _activeGattConnections--;
    }
  }

  /// Broadcast [packetBytes] to up to 5 currently known peers concurrently.
  ///
  /// [retryOnAllFailure] — when true, if EVERY peer send returns false (all
  /// GATT slots were capped, or no peers present), the packet is added to the
  /// retry queue and re-attempted every [_retryIntervalMs] ms for up to
  /// [_retryMaxAgeMs] ms. Use for SOS packets where delivery is critical.
  /// For attendance/social, the lane-level re-broadcast timers cover retries.
  ///
  /// [requireAck] — when true, each peer send uses ATT Write Request
  /// (withoutResponse: false) so the BLE stack waits for peer confirmation.
  /// Set to true for originated SOS and attendance packets. Leave false for
  /// relay packets (throughput matters more for relay hops).
  ///
  /// The public signature stays `void` so existing call sites (MeshService)
  /// need no changes — the async work runs fire-and-forget internally.
  void broadcastPacket(
    List<int> packetBytes, {
    bool retryOnAllFailure = false,
    bool requireAck = false,
  }) {
    _broadcastAsync(
      packetBytes,
      retryOnAllFailure: retryOnAllFailure,
      requireAck: requireAck,
    ).ignore();
  }

  Future<void> _broadcastAsync(
    List<int> packetBytes, {
    bool retryOnAllFailure = false,
    bool requireAck = false,
  }) async {
    if (!_running) return;

    // Select up to 5 peers sorted by RSSI descending (strongest signal first).
    //
    // Previous bug: used _peerDevices.values.take(5) which always picked the
    // first 5 peers by insertion order (oldest peers). With 6+ peers in range,
    // the most recently discovered peer (potentially the closest) was never
    // reached. SOS and attendance packets consistently missed newer students
    // even when they were physically closer to the broadcaster.
    //
    // Fix: sort by _peerRssi descending before take(5). Strongest signal =
    // physically closest = most likely to have a successful GATT connection.
    // This also improves SOS delivery — the closest relay node is always tried
    // first, minimising the chance of all 5 slots going to distant peers.
    final sortedIds = _peerDevices.keys.toList()
      ..sort((a, b) =>
          (_peerRssi[b] ?? -100).compareTo(_peerRssi[a] ?? -100));
    final devices = sortedIds
        .take(5)
        .map((id) => _peerDevices[id]!)
        .toList();

    if (devices.isEmpty) {
      // No peers in range — queue immediately if retry is enabled.
      // Re-check _running: stop() could have fired between the guard above
      // and here (unlikely but possible in Dart's cooperative scheduler).
      if (retryOnAllFailure && _running) _enqueueForRetry(packetBytes);
      return;
    }

    // Send to all peers concurrently and collect success flags.
    final results = await Future.wait(
      devices.map((d) => sendPacketToPeer(d, packetBytes, requireAck: requireAck)),
    );

    // If every send failed (all GATT slots busy at the same moment), queue.
    // Re-check _running: stop() may have been called during the awaits above.
    if (retryOnAllFailure && _running && results.every((success) => !success)) {
      _enqueueForRetry(packetBytes);
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
    // Update watchdog heartbeat on EVERY scan callback — including empty results.
    // Reason: in an empty room with no BLE peers, results is always empty and
    // _lastScanActivityTime would never update. After 3× the duty cycle the
    // watchdog would false-fire and restart unnecessarily. Updating here confirms
    // the BLE stack is alive and delivering callbacks regardless of peer count.
    _lastScanActivityTime = DateTime.now();

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
      _peerLastSeen[deviceId] = DateTime.now(); // for stale-peer eviction

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

  // ── Private — Stale peer eviction ────────────────────────────────────────

  /// Remove peers not seen in the last 60 seconds.
  ///
  /// Called every 30 s by [_evictionTimer]. Prevents [broadcastPacket] from
  /// trying to GATT-connect to devices that have walked out of range, which
  /// ties up GATT slots for the full 5-second connect timeout.
  void _evictStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    final stale = _peerLastSeen.entries
        .where((e) => e.value.isBefore(cutoff))
        .map((e) => e.key)
        .toList();

    if (stale.isEmpty) return;

    for (final id in stale) {
      _peerRssi.remove(id);
      _peerDevices.remove(id);
      _peerLastSeen.remove(id);
    }
    onPeerCountChanged?.call(_peerRssi.length);
    debugPrint('[BLE] evicted ${stale.length} stale peer(s) — '
        '${_peerRssi.length} peer(s) remain');
  }

  // ── Private — Adapter state ───────────────────────────────────────────────

  void _onAdapterState(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.on && _running) {
      _startScanOnce();
    } else if (state != BluetoothAdapterState.on) {
      _peerRssi.clear();
      _peerDevices.clear();
      _peerLastSeen.clear();
      onPeerCountChanged?.call(0);
    }
  }

  // ── Private — GATT retry queue (Fix 2C) ──────────────────────────────────

  /// Add [packetBytes] to the retry queue if room is available.
  ///
  /// Duplicate detection: we don't dedup by content (too expensive for raw
  /// bytes). Instead the queue is small (max 8) and short-lived (30 s TTL),
  /// so at worst a packet is retried a handful of times.
  void _enqueueForRetry(List<int> packetBytes) {
    if (_retryQueue.length >= _retryQueueMaxSize) {
      // Drop oldest entry to make room — fresh data is more useful.
      _retryQueue.removeAt(0);
    }
    _retryQueue.add((
      bytes: packetBytes,
      expiresAt: DateTime.now().add(
        const Duration(milliseconds: _retryMaxAgeMs),
      ),
    ));
    debugPrint('[BLE] Retry queue: ${_retryQueue.length} packet(s) pending');
  }

  /// Drain expired entries and re-broadcast the rest.
  ///
  /// Called every [_retryIntervalMs] ms by [_retryTimer]. Uses the plain
  /// `broadcastPacket` path WITHOUT `retryOnAllFailure` to avoid infinite
  /// re-queuing if peers are still unavailable.
  void _processRetryQueue() {
    if (!_running || _retryQueue.isEmpty) return;

    final now = DateTime.now();
    _retryQueue.removeWhere((entry) => entry.expiresAt.isBefore(now));

    if (_retryQueue.isEmpty) return;
    if (_peerDevices.isEmpty) return; // No peers — keep in queue, try next cycle.

    debugPrint('[BLE] Retry queue: flushing ${_retryQueue.length} packet(s)');

    // Snapshot and clear — if sends fail again the caller (SOS re-broadcast)
    // will re-add. We don't want stale entries accumulating indefinitely.
    final pending = List.of(_retryQueue);
    _retryQueue.clear();

    for (final entry in pending) {
      // No retryOnAllFailure — avoids infinite re-queue loops.
      // requireAck is omitted (defaults false) for retry packets because we
      // cannot recover the original packet type from raw bytes. SOS re-broadcast
      // from SosService already re-originates with requireAck=true via sendPacket;
      // the retry queue is a last-resort fallback for connection-failure scenarios.
      _broadcastAsync(entry.bytes).ignore();
    }
  }

  // ── Private — BLE health watchdog (Fix 1C) ────────────────────────────────

  /// Periodic health check — verifies the duty-cycle machinery is still alive.
  ///
  /// Checks two conditions:
  ///   1. The duty-cycle timer is active (not null and not cancelled).
  ///   2. Scan results have arrived within 3× the expected cycle period,
  ///      confirming the BLE scanner is actually delivering data.
  ///
  /// If either check fails while [_running] is true, the duty cycle is
  /// restarted immediately. This recovers from silent Dart timer death
  /// that can occur on heavily memory-pressured devices even with a WakeLock.
  void _checkBleHealth() {
    if (!_running) return;

    bool needsRestart = false;

    // Check 1: duty-cycle timer must be alive.
    if (_dutyCycleTimer == null || !_dutyCycleTimer!.isActive) {
      debugPrint('[BLE] Watchdog: duty-cycle timer is dead — will restart');
      needsRestart = true;
    }

    // Check 2: scan activity must be recent.
    // Allow 3× the full duty cycle as tolerance (Doze may have delayed one cycle).
    if (!needsRestart && _lastScanActivityTime != null) {
      final cycleSecs =
          (_scanDuration() + _sleepDuration()).inSeconds.clamp(1, 3600);
      final staleSecs = DateTime.now()
          .difference(_lastScanActivityTime!)
          .inSeconds;
      if (staleSecs > cycleSecs * 3) {
        debugPrint('[BLE] Watchdog: no scan activity for ${staleSecs}s '
            '(expected < ${cycleSecs * 3}s) — will restart');
        needsRestart = true;
      }
    }

    if (needsRestart) {
      _restartDutyCycle();
      // Also reschedule the Doze alarm in case it expired while we were stuck.
      _scheduleDozeAlarm().ignore();
    }
  }

  // ── Private — Deep-Doze AlarmManager (Fix 1B) ────────────────────────────

  /// Called by VextAlarmReceiver when the Doze alarm fires.
  ///
  /// Restarts the duty-cycle timer (the normal Dart timer was stalled by Doze)
  /// and immediately schedules the next alarm so protection is continuous.
  void _onDozeAlarmEvent(dynamic event) {
    if (!_running) return;
    debugPrint('[BLE] Doze alarm fired — restarting duty cycle');
    _restartDutyCycle();
    // Reschedule — setExactAndAllowWhileIdle is one-shot, must re-arm each time.
    _scheduleDozeAlarm().ignore();
  }

  /// Schedule a one-shot Doze-safe alarm via AlarmManager (Fix 1B).
  ///
  /// Interval = full duty-cycle period (active + sleep). In idle mode this is
  /// 31 seconds. The alarm is a safety net: if the normal Dart timer fires on
  /// schedule it restarts the scan before the alarm fires. If Doze stalls the
  /// timer, the alarm wakes the device and we restart from here.
  Future<void> _scheduleDozeAlarm() async {
    final intervalMs =
        _scanDuration().inMilliseconds + _sleepDuration().inMilliseconds;
    try {
      await _alarmManagerChannel.invokeMethod<bool>(
        'scheduleDozeAlarm',
        {'intervalMs': intervalMs},
      );
    } catch (e) {
      debugPrint('[BLE] scheduleDozeAlarm failed: $e');
    }
  }

  /// Cancel any pending Doze alarm (called on BLE stop).
  Future<void> _cancelDozeAlarm() async {
    try {
      await _alarmManagerChannel.invokeMethod<bool>('cancelDozeAlarm');
    } catch (_) {}
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
