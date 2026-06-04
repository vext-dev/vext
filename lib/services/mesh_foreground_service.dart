// ── MeshForegroundService — Android Foreground Service Keepalive ───────────────
//
// Problem: Android kills the app process when the screen turns off if there is
// no foreground service. This stops BLE scanning, the duty-cycle timer, and all
// GATT operations silently — the mesh goes dark the moment a relay phone is
// pocketed.
//
// Solution: Start an Android foreground service (persistent notification) that
// keeps the process alive. The existing BLE stack in the main Flutter isolate
// continues running untouched. The background isolate is minimal — it only
// exists to hold the foreground service alive and handle notification updates.
//
// Architecture:
//   Main isolate  → BleTransportLayer, MeshService, all Riverpod providers
//   Background isolate → foreground notification + message pump (this file)
//
// The two isolates communicate via flutter_background_service's invoke/on API:
//   Main → Background:  'updateNotification' {content: "2 peers nearby"}
//   Main → Background:  'stopService'
//
// Usage (called by BleStateNotifier in ble_provider.dart):
//   await MeshForegroundService.configure();   // once, in main()
//   await MeshForegroundService.start();       // when BLE starts
//   MeshForegroundService.updateNotification(peerCount);  // on peer change
//   await MeshForegroundService.stop();        // when BLE stops
//
// Requires flutter_background_service: ^5.0.8 (already in pubspec.yaml).
//
// Android 14 note:
//   targetSdk 34+ requires foregroundServiceType="connectedDevice" on the
//   BackgroundService <service> tag. This is handled in AndroidManifest.xml
//   via tools:node="merge" on the plugin's service class.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../core/app_constants.dart';

// ── Background isolate entry point ────────────────────────────────────────────
//
// @pragma('vm:entry-point') prevents the Dart tree-shaker from removing this
// function in release builds. Without it, the background isolate will crash
// on first start in --release mode with "no such method" from the engine.
//
// This function runs in a SEPARATE Dart isolate from the main UI isolate.
// It cannot access Riverpod providers, the BLE stack, or any shared state.
// Its only job: hold the foreground service alive and respond to messages.

@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  // On Android the service instance is an AndroidServiceInstance.
  // Cast once and keep — avoids repeated is-checks in callbacks.
  final androidService =
      service is AndroidServiceInstance ? service : null;

  // ── Ensure foreground mode ────────────────────────────────────────────────
  // isForegroundMode: true in AndroidConfiguration starts us in foreground,
  // but call setAsForegroundService() explicitly for safety on some OEM ROMs
  // (Samsung / Xiaomi) that downgrade the service if the notification is not
  // shown fast enough.
  await androidService?.setAsForegroundService();

  // ── Message: updateNotification ───────────────────────────────────────────
  // Sent by the main isolate whenever peer count changes.
  // Data format: { 'content': 'Mesh active · 2 peers nearby' }
  service.on('updateNotification').listen((data) {
    final content = data?['content'] as String? ??
        AppConstants.foregroundServiceNotificationBody;
    androidService?.setForegroundNotificationInfo(
      title: AppConstants.foregroundServiceNotificationTitle,
      content: content,
    );
  });

  // ── Message: stopService ──────────────────────────────────────────────────
  // Sent by the main isolate when BLE scanning is stopped (user action or
  // app going to login screen). Removes the persistent notification and
  // allows Android to manage the process normally again.
  service.on('stopService').listen((_) {
    debugPrint('[FGService] Stopping on request from main isolate');
    service.stopSelf();
  });

  // ── Heartbeat ─────────────────────────────────────────────────────────────
  // Keeps the isolate alive. Without at least one active listener or timer,
  // the Dart event loop exits and the isolate dies (taking the service with it).
  // 30-second interval is far enough apart to have negligible battery impact.
  Timer.periodic(const Duration(seconds: 30), (_) {
    // No-op. The timer itself is sufficient to keep the event loop alive.
    // Do NOT put heavy logic here — this runs in a background process.
  });

  debugPrint('[FGService] Background isolate started — foreground service active');
}

// ── MeshForegroundService ─────────────────────────────────────────────────────

class MeshForegroundService {
  MeshForegroundService._(); // static-only class

  static final _service = FlutterBackgroundService();

  // ── configure ─────────────────────────────────────────────────────────────

  /// Configure the background service. Call ONCE in main() before runApp().
  ///
  /// Sets up the notification channel, entry point, and autoStart=false so
  /// the service only runs when VEXT explicitly starts it. Does NOT start
  /// the service — call [start] when BLE begins.
  static Future<void> configure() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundStart,

        // false = we start the service manually when BLE starts.
        // Do not auto-start on boot — the user must open the app first.
        autoStart: false,

        // true = start as a foreground service with a persistent notification.
        // false would be a background service, which Android 8+ severely limits
        // (killed within minutes). We always need foreground mode for BLE mesh.
        isForegroundMode: true,

        // Notification channel ID — must match AppConstants and the channel
        // created in the Android notification system. This channel is declared
        // in the plugin's own registration; we reference it by ID here.
        notificationChannelId: AppConstants.foregroundServiceChannelId,

        // Initial notification content shown when the service first starts
        // (before the first updateNotification message arrives from the main
        // isolate). Replaced within ~1 second by real peer count.
        initialNotificationTitle: AppConstants.foregroundServiceNotificationTitle,
        initialNotificationContent: AppConstants.foregroundServiceNotificationBody,

        // Notification ID — must be non-zero. Used by Android to identify
        // the foreground notification. Matches AppConstants.
        foregroundServiceNotificationId:
            AppConstants.foregroundServiceNotificationId,
      ),

      // iOS: autoStart=false — we do not implement a background iOS mode
      // in this milestone. BLE background on iOS requires different entitlements
      // (bluetooth-central background mode in Info.plist) and is out of scope.
      iosConfiguration: IosConfiguration(
        autoStart: false,
      ),
    );

    debugPrint('[FGService] Configured — notification channel: '
        '${AppConstants.foregroundServiceChannelId}');
  }

  // ── start ─────────────────────────────────────────────────────────────────

  /// Start the foreground service. Call when BLE scanning begins.
  ///
  /// Safe to call multiple times — if the service is already running this is
  /// a no-op from the Android side (startForegroundService is idempotent).
  static Future<void> start() async {
    final running = await _service.isRunning();
    if (running) {
      debugPrint('[FGService] Already running — skipping start');
      return;
    }

    final started = await _service.startService();
    debugPrint('[FGService] startService() → $started');
  }

  // ── stop ──────────────────────────────────────────────────────────────────

  /// Stop the foreground service. Call when BLE scanning stops.
  ///
  /// Sends a 'stopService' message to the background isolate, which calls
  /// service.stopSelf(). The persistent notification is removed immediately.
  static Future<void> stop() async {
    final running = await _service.isRunning();
    if (!running) return;

    _service.invoke('stopService');
    debugPrint('[FGService] stopService invoked');
  }

  // ── updateNotification ────────────────────────────────────────────────────

  /// Update the persistent notification text with current peer count.
  ///
  /// Safe to call even when the service is not running — invoke() is fire-
  /// and-forget and silently does nothing if the background isolate is gone.
  static void updateNotification(int peerCount) {
    final content = peerCount == 0
        ? 'Mesh active · scanning for peers…'
        : peerCount == 1
            ? 'Mesh active · 1 peer nearby'
            : 'Mesh active · $peerCount peers nearby';

    _service.invoke('updateNotification', {'content': content});
  }
}
