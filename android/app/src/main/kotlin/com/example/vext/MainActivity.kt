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
// ──────────────────────────────────────────────────────────────────────────────

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Lazily initialised — context (this) is not available until after super.onCreate().
    private lateinit var bleAdvertiser: BleAdvertiser
    private lateinit var gattServer: VextGattServer

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
    //
    // IMPORTANCE_LOW: silent, no heads-up, stays in notification drawer.
    // Required by the BLE mesh foreground service (flutter_background_service).
    // Must exist BEFORE startForeground() is called — hence created here in
    // onCreate() before any Dart/Flutter code runs.
    private fun createVextNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "vext_mesh_channel",              // must match AppConstants.foregroundServiceChannelId
                "VigilantMesh Service",           // user-visible name in Settings → Notifications
                NotificationManager.IMPORTANCE_LOW // silent — no sound, no popup, stays in drawer
            ).apply {
                description = "VEXT BLE mesh is active in the background"
                setShowBadge(false)              // no badge on app icon
                enableVibration(false)
                enableLights(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    // ── vext_sos_channel — FCM SOS emergency alerts ────────────────────────────
    //
    // The handleSOSAlert Cloud Function sends FCM notifications with:
    //   android.notification.channelId = "vext_sos_channel"
    //   android.priority = "high"
    //
    // On Android 8.0+ (API 26+), if the target channel does not exist, the OS
    // SILENTLY DROPS the notification — no sound, no banner, no alert.
    // Channel must exist on the device before the first FCM push is received.
    //
    // IMPORTANCE_HIGH: shows a heads-up banner, plays the default alert sound,
    // vibrates. Correct for a safety-critical SOS emergency alert.
    private fun createVextSosNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "vext_sos_channel",              // must match channelId in handleSOSAlert.ts
                "SOS Emergency Alerts",          // user-visible name in Settings → Notifications
                NotificationManager.IMPORTANCE_HIGH // heads-up banner + sound + vibration
            ).apply {
                description = "Emergency SOS alerts from the campus mesh network"
                setShowBadge(true)
                enableVibration(true)
                enableLights(true)
                lightColor = 0xFFEF4444.toInt()  // red — matches SOS UI colour
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
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
    }

    // ── Cleanup on activity destroy ────────────────────────────────────────────
    //
    // Android may call onDestroy() without a prior onPause() (e.g. force-stop).
    // Clean up native BLE resources so the system doesn't keep the BLE stack
    // allocated after the app is gone.

    override fun onDestroy() {
        if (::bleAdvertiser.isInitialized) {
            bleAdvertiser.stopAdvertisingInternal()
        }
        if (::gattServer.isInitialized) {
            gattServer.stopServerInternal()
        }
        super.onDestroy()
    }
}
