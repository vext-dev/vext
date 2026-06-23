package com.vext.vext_app

// ── VextGattServer — Kotlin GATT Server (Peripheral/Server Role) ──────────────
//
// flutter_blue_plus is central-only (scanner + GATT client). To receive packets
// from other VEXT mesh nodes that connect as GATT clients, we need a native
// GATT server. This class implements that server.
//
// Architecture:
//   Dart (MeshService) → BleTransportLayer → VextGattServer
//                                          ← EventChannel (incoming packets)
//
// Channels:
//   MethodChannel "com.vext.vext_app/gatt_server"
//     startServer()  → Boolean
//     stopServer()   → Boolean
//     isRunning()    → Boolean
//
//   EventChannel "com.vext.vext_app/gatt_packets"
//     Emits List<Int> (packet bytes) whenever a peer writes to the write
//     characteristic. Dart converts this to Uint8List.
//
// GATT Service Layout:
//   Service UUID:       6E400001-B5A3-F393-E0A9-E50E24DCCA9E (VEXT primary)
//   Write Char UUID:    6E400002-B5A3-F393-E0A9-E50E24DCCA9E (receive packets)
//
// Design notes:
//   • Each GATT write fires a packet up the event channel to Dart.
//   • No notify characteristic in M3 — GATT is write-only from client perspective.
//   • Respond GATT_SUCCESS to every write to prevent client timeout.
//   • Multiple concurrent connections are supported (Android supports ~7 peripheral connections).
//   • Server runs until stopServer() is called or the app is destroyed.
//
// ──────────────────────────────────────────────────────────────────────────────

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.content.Context
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

class VextGattServer(private val context: Context) :
    MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL_NAME = "com.vext.vext_app/gatt_server"
        const val EVENT_CHANNEL_NAME  = "com.vext.vext_app/gatt_packets"

        // Must match AppConstants in Dart.
        private val SERVICE_UUID        = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        private val WRITE_CHAR_UUID     = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    }

    // ── State ──────────────────────────────────────────────────────────────────

    private var gattServer: BluetoothGattServer? = null

    @Volatile
    private var isRunning = false

    // EventChannel sink — set when Dart subscribes, cleared on cancel.
    private var eventSink: EventChannel.EventSink? = null

    // ── Lazy helpers ───────────────────────────────────────────────────────────

    private val bluetoothManager: BluetoothManager? by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    }

    // ── GATT server callback ───────────────────────────────────────────────────

    private val gattServerCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(
            device: BluetoothDevice,
            status: Int,
            newState: Int
        ) {
            // Connection state changes are informational — no action needed.
            // Multiple simultaneous GATT client connections are fine.
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            // Only process writes to our write characteristic.
            if (characteristic.uuid != WRITE_CHAR_UUID) {
                if (responseNeeded) {
                    gattServer?.sendResponse(
                        device, requestId,
                        BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null
                    )
                }
                return
            }

            // Always respond success so the GATT client doesn't time out.
            if (responseNeeded) {
                gattServer?.sendResponse(
                    device, requestId,
                    BluetoothGatt.GATT_SUCCESS, 0, null
                )
            }

            // Forward bytes to Dart via event channel.
            val bytes = value ?: return
            if (bytes.isEmpty()) return

            // EventSink calls must happen on the main thread.
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(bytes.map { it.toInt() and 0xFF })
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            // Service added successfully — server is now discoverable by GATT clients.
        }
    }

    // ── MethodCallHandler ──────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startServer" -> startServer(result)
            "stopServer"  -> stopServer(result)
            "isRunning"   -> result.success(isRunning)
            else          -> result.notImplemented()
        }
    }

    // ── EventChannel.StreamHandler ─────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ── Server lifecycle ───────────────────────────────────────────────────────

    private fun startServer(result: Result) {
        if (isRunning) {
            result.success(true)
            return
        }

        val manager = bluetoothManager
        if (manager == null) {
            result.error("BLE_UNAVAILABLE", "BluetoothManager not available", null)
            return
        }

        try {
            val server = manager.openGattServer(context, gattServerCallback)
            if (server == null) {
                result.error("GATT_OPEN_FAILED", "openGattServer returned null", null)
                return
            }

            // Build the VEXT GATT service.
            val service = BluetoothGattService(
                SERVICE_UUID,
                BluetoothGattService.SERVICE_TYPE_PRIMARY
            )

            // Write characteristic — receives full MeshPacket bytes from GATT clients.
            val writeChar = BluetoothGattCharacteristic(
                WRITE_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                        BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            service.addCharacteristic(writeChar)

            val added = server.addService(service)
            if (!added) {
                server.close()
                result.error("SERVICE_ADD_FAILED", "addService returned false", null)
                return
            }

            gattServer = server
            isRunning = true
            result.success(true)

        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission required", null)
        } catch (e: Exception) {
            result.error("GATT_EXCEPTION", e.message ?: "Unknown exception", null)
        }
    }

    private fun stopServer(result: Result) {
        stopServerInternal()
        result.success(true)
    }

    /**
     * Internal stop — called from MainActivity.onDestroy() without a Flutter result.
     */
    fun stopServerInternal() {
        try {
            gattServer?.close()
        } catch (e: Exception) {
            // Ignore — adapter may already be off.
        } finally {
            gattServer = null
            isRunning = false
        }
    }
}
