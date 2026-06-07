package com.example.vext

// ── MainActivity — Flutter entry point + platform channel registration ─────────
//
// Registers all MethodChannels and EventChannels used by VEXT's native Kotlin
// BLE components. Flutter plugins (flutter_blue_plus, firebase_messaging, etc.)
// self-register via their own GeneratedPluginRegistrant — do NOT call that here,
// FlutterActivity handles it automatically.
//
// Channels registered here:
//   BleAdvertiser MethodChannel  "com.example.vext/ble_advertiser"
//     → BLE peripheral advertising (startAdvertising / stopAdvertising)
//
//   VextGattServer MethodChannel "com.example.vext/gatt_server"
//     → GATT server lifecycle (startServer / stopServer)
//
//   VextGattServer EventChannel  "com.example.vext/gatt_packets"
//     → Stream of incoming packet bytes from GATT client writes
//
//   WakeLock MethodChannel       "com.example.vext/wake_lock"
//     → PARTIAL_WAKE_LOCK acquire/release (Fix 1A)
//
//   AlarmManager MethodChannel   "com.example.vext/alarm_manager"
//     → setExactAndAllowWhileIdle scheduling for deep-Doze survival (Fix 1B)
//
//   Alarm Events EventChannel    "com.example.vext/alarm_events"
//     → Stream of "scanRestart" strings fired by VextAlarmReceiver (Fix 1B)
//
// ──────────────────────────────────────────────────────────────────────────────

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Lazily initialised — context (this) is not available until after super.onCreate().
    private lateinit var bleAdvertiser: BleAdvertiser
    private lateinit var gattServer: VextGattServer

    // ── WakeLock ───────────────────────────────────────────────────────────────
    //
    // A PARTIAL_WAKE_LOCK keeps the CPU running while the screen is off, which
    // prevents Android from stalling the Dart event loop and the BLE duty-cycle
    // timers. The WAKE_LOCK permission is already declared in AndroidManifest.xml.
    //
    // Lifecycle: acquired when BLE scanning starts (Dart calls 'acquireWakeLock'),
    // released when BLE stops (Dart calls 'releaseWakeLock') or in onDestroy().
    //
    // Tag uses the reverse-domain + colon format required by Android Lint.
    private var wakeLock: PowerManager.WakeLock? = null
    private val wakeLockTag = "vext:MeshScanWakeLock"

    // ── onCreate — notification channel setup ──────────────────────────────────
    //
    // The VEXT mesh foreground service (flutter_background_service) posts a
    // persistent notification on the 'vext_mesh_channel' channel. Android 8.0+
    // (API 26+) requires the channel to exist BEFORE startForeground() is called.
    // If the channel is missing, startForeground() throws:
    //   CannotPostForegroundServiceNotificationException: Bad notification
    // and crashes the entire process.
    //
    // Creating the channel here (synchronously in onCreate, before any Dart code
    // runs) is the earliest possible point and guarantees it exists for the
    // lifetime of the process.
    //
    // IMPORTANCE_LOW: shows the notification silently — no sound, no heads-up
    // popup. Correct for a persistent background service indicator.
    // IMPORTANCE_NONE would make it invisible, which Android rejects for
    // foreground service notifications.

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createVextNotificationChannel()
        createVextSosNotificationChannel()
    }

    // ── vext_mesh_channel — foreground service persistent notification ─────────
    private fun createVextNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "vext_mesh_channel",
                "VigilantMesh Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VEXT BLE mesh is active in the background"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    // ── vext_sos_channel — FCM SOS emergency alerts ────────────────────────────
    private fun createVextSosNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "vext_sos_channel",
                "SOS Emergency Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Emergency SOS alerts from the campus mesh network"
                setShowBadge(true)
                enableVibration(true)
                enableLights(true)
                lightColor = 0xFFEF4444.toInt()
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    // ── FlutterActivity lifecycle ──────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ── BleAdvertiser ──────────────────────────────────────────────────────
        bleAdvertiser = BleAdvertiser(this)
        MethodChannel(messenger, BleAdvertiser.CHANNEL_NAME)
            .setMethodCallHandler(bleAdvertiser)

        // ── VextGattServer ─────────────────────────────────────────────────────
        gattServer = VextGattServer(this)
        MethodChannel(messenger, VextGattServer.METHOD_CHANNEL_NAME)
            .setMethodCallHandler(gattServer)
        EventChannel(messenger, VextGattServer.EVENT_CHANNEL_NAME)
            .setStreamHandler(gattServer)

        // ── WakeLock channel ───────────────────────────────────────────────────
        // Called by BleTransportLayer.start() / stop() in Dart.
        MethodChannel(messenger, "com.example.vext/wake_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireWakeLock" -> { acquireVextWakeLock(); result.success(true) }
                    "releaseWakeLock" -> { releaseVextWakeLock(); result.success(true) }
                    else -> result.notImplemented()
                }
            }

        // ── AlarmManager channel (Fix 1B) ──────────────────────────────────────
        //
        // 'scheduleDozeAlarm' — schedule a one-shot setExactAndAllowWhileIdle alarm.
        //   Args: { "intervalMs": Long }
        //   The alarm fires VextAlarmReceiver which pushes to the alarm_events
        //   EventChannel. BleTransportLayer reschedules after every receipt so
        //   the Doze safety net runs continuously while BLE is active.
        //
        // 'cancelDozeAlarm' — cancel any pending alarm (called on BLE stop).
        //
        // Falls back to setAndAllowWhileIdle (inexact, still Doze-exempt) on
        // Android 12+ if the user has not granted SCHEDULE_EXACT_ALARM.
        MethodChannel(messenger, "com.example.vext/alarm_manager")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleDozeAlarm" -> {
                        val intervalMs = (call.argument<Any>("intervalMs") as? Number)
                            ?.toLong() ?: 31_000L
                        scheduleDozeAlarm(intervalMs)
                        result.success(true)
                    }
                    "cancelDozeAlarm" -> {
                        cancelDozeAlarm()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Alarm Events EventChannel (Fix 1B) ─────────────────────────────────
        //
        // Dart subscribes when BLE starts. When VextAlarmReceiver fires, it calls
        // eventSink.success("scanRestart"), which this channel delivers to Dart.
        // BleTransportLayer listens and calls _restartDutyCycle() on each event.
        EventChannel(messenger, "com.example.vext/alarm_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    VextAlarmReceiver.eventSink = events
                    Log.d("VEXT", "[AlarmEvents] Dart subscribed — eventSink set")
                }
                override fun onCancel(arguments: Any?) {
                    VextAlarmReceiver.eventSink = null
                    Log.d("VEXT", "[AlarmEvents] Dart unsubscribed — eventSink cleared")
                }
            })
    }

    // ── WakeLock helpers ───────────────────────────────────────────────────────

    private fun acquireVextWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, wakeLockTag).apply {
            // 6-hour safety timeout. A campus day (back-to-back classes) can run
            // 8+ hours, but any single BLE session (attendance class, SOS event)
            // is well under 6 hours. The Dart side always calls releaseWakeLock()
            // on BLE stop, so in practice the WakeLock is released long before
            // this timeout fires. The previous 10-minute timeout was a real bug:
            // after minute 10 the WakeLock silently expired, Doze resumed, and the
            // duty-cycle timer stalled — exactly the failure Fix 1A was meant to prevent.
            acquire(6 * 60 * 60 * 1000L)
        }
    }

    private fun releaseVextWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    // ── AlarmManager helpers (Fix 1B) ──────────────────────────────────────────

    /**
     * Schedule a one-shot alarm to fire [intervalMs] from now.
     *
     * Uses setExactAndAllowWhileIdle() on Android 12+ when permitted, which is
     * the only API guaranteed to fire during deep Doze.
     *
     * Fallback on Android 12+ without SCHEDULE_EXACT_ALARM permission:
     *   setAndAllowWhileIdle() — still Doze-exempt, just not time-exact.
     *   Adequate for a BLE scan restart: a few seconds' jitter is acceptable.
     *
     * On Android 5.1 and below (API 22-): setExact() — Doze did not exist.
     */
    private fun scheduleDozeAlarm(intervalMs: Long) {
        val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pi = buildAlarmPendingIntent(PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        val triggerAt = System.currentTimeMillis() + intervalMs

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                // Android 12+: prefer exact, fall back to inexact if not permitted.
                if (am.canScheduleExactAlarms()) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    Log.d("VEXT", "[Alarm] setExactAndAllowWhileIdle in ${intervalMs}ms")
                } else {
                    // Inexact but still fires during Doze — acceptable for scan restart.
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    Log.d("VEXT", "[Alarm] setAndAllowWhileIdle (no exact permission) in ${intervalMs}ms")
                }
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                // Android 6–11: setExactAndAllowWhileIdle doesn't require permission.
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                Log.d("VEXT", "[Alarm] setExactAndAllowWhileIdle in ${intervalMs}ms")
            }
            else -> {
                // Android 5.1 and below — Doze doesn't exist, plain setExact is fine.
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        }
    }

    /**
     * Cancel any pending Doze alarm. Called when BLE scanning stops.
     * Safe to call if no alarm is pending — FLAG_NO_CREATE returns null in that case.
     */
    private fun cancelDozeAlarm() {
        val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pi = buildAlarmPendingIntent(PendingIntent.FLAG_NO_CREATE) ?: return
        am.cancel(pi)
        pi.cancel()
        Log.d("VEXT", "[Alarm] Doze alarm cancelled")
    }

    /**
     * Build the PendingIntent that targets [VextAlarmReceiver].
     * [flags] should be FLAG_UPDATE_CURRENT when scheduling, FLAG_NO_CREATE when cancelling.
     */
    private fun buildAlarmPendingIntent(flags: Int): PendingIntent? {
        val intent = Intent(this, VextAlarmReceiver::class.java).apply {
            action = VextAlarmReceiver.ACTION
        }
        val immutableFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags or PendingIntent.FLAG_IMMUTABLE
        } else {
            flags
        }
        return PendingIntent.getBroadcast(
            this,
            VextAlarmReceiver.REQUEST_CODE,
            intent,
            immutableFlags
        )
    }

    // ── Cleanup on activity destroy ────────────────────────────────────────────

    override fun onDestroy() {
        if (::bleAdvertiser.isInitialized) bleAdvertiser.stopAdvertisingInternal()
        if (::gattServer.isInitialized) gattServer.stopServerInternal()
        releaseVextWakeLock()
        // Cancel the Doze alarm on destroy — the app is gone, no need to wake up.
        cancelDozeAlarm()
        super.onDestroy()
    }
}
