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

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Lazily initialised — context (this) is not available until after super.onCreate().
    private lateinit var bleAdvertiser: BleAdvertiser
    private lateinit var gattServer: VextGattServer

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
