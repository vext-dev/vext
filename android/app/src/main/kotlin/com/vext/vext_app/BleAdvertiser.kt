package com.vext.vext_app

// ── BleAdvertiser — Kotlin BLE Peripheral Advertising ─────────────────────────
//
// flutter_blue_plus is central (scanner) mode only. Peripheral advertising
// requires Android's BluetoothLeAdvertiser API, exposed to Flutter via a
// MethodChannel.
//
// Channel: "com.vext.vext_app/ble_advertiser"
// Methods:
//   startAdvertising(payload: ByteArray?) → Boolean
//     Starts BLE advertising with the VEXT service UUID.
//     If payload is non-null (max 17 bytes), it is included as manufacturer data.
//     Returns true on success, throws on failure.
//   stopAdvertising() → Boolean
//     Stops advertising. Always returns true.
//   isAdvertising() → Boolean
//     Returns current advertising state.
//
// Design notes:
//   • setConnectable(true) so GATT clients (peer devices) can connect back.
//   • 18-byte MeshPacket.toAdvertisementBytes() payload is passed from Dart.
//     It is trimmed to 17 bytes (max manufacturer data with 1-byte header).
//   • setTimeout(0) = advertise indefinitely (cancelled only via stopAdvertising).
//   • Gracefully handles cases where BLE adapter is absent or unsupported.
//
// ──────────────────────────────────────────────────────────────────────────────

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class BleAdvertiser(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.vext.vext_app/ble_advertiser"

        // VEXT primary service UUID — must match AppConstants.bleServiceUuid in Dart.
        private val VEXT_SERVICE_UUID =
            ParcelUuid.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")

        // Manufacturer-specific data vendor ID. 0xFFFE is a test/research ID
        // (non-reserved for academic use — replace with a real BT SIG ID in production).
        private const val VEXT_MANUFACTURER_ID = 0xFFFE

        // Maximum bytes allowed in Android manufacturer-specific AD structure.
        // 31-byte PDU limit − flags(3) − service UUID(18) − manufacturer header(2) = 8 bytes.
        // We use 17 bytes in scan response slot instead (no UUID repeated there).
        private const val MAX_MANUFACTURER_BYTES = 17
    }

    // ── State ──────────────────────────────────────────────────────────────────

    @Volatile
    private var isAdvertising = false

    // Kept so stopAdvertising() can cancel the correct callback instance.
    private var activeCallback: AdvertiseCallback? = null

    // ── Lazy accessors — null-safe ──────────────────────────────────────────────

    private val bluetoothManager: BluetoothManager? by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    }

    private val bluetoothAdapter: BluetoothAdapter? get() = bluetoothManager?.adapter

    private val leAdvertiser: BluetoothLeAdvertiser? get() = bluetoothAdapter?.bluetoothLeAdvertiser

    // ── MethodCallHandler ──────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startAdvertising" -> {
                // payload is passed as a List<Int> from Dart's Uint8List
                val rawPayload = call.argument<List<Int>>("payload")
                val payload = rawPayload?.map { it.toByte() }?.toByteArray()
                startAdvertising(payload, result)
            }
            "stopAdvertising" -> stopAdvertising(result)
            "isAdvertising"   -> result.success(isAdvertising)
            else              -> result.notImplemented()
        }
    }

    // ── Public API ─────────────────────────────────────────────────────────────

    private fun startAdvertising(payload: ByteArray?, result: Result) {
        val advertiser = leAdvertiser
        if (advertiser == null) {
            result.error(
                "BLE_UNAVAILABLE",
                "BluetoothLeAdvertiser is not available on this device.",
                null
            )
            return
        }

        // If already advertising with a previous call, stop first.
        if (isAdvertising) {
            stopAdvertisingInternal()
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)   // Required: allows GATT clients to connect.
            .setTimeout(0)          // 0 = advertise until explicitly stopped.
            .build()

        // Primary advertisement: service UUID (for scanner's withServices filter).
        val primaryData = AdvertiseData.Builder()
            .addServiceUuid(VEXT_SERVICE_UUID)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        // Scan response: 18-byte MeshPacket header as manufacturer data.
        // Scan response is returned when the scanner sends a SCAN_REQ — not
        // included in passive scans, but flutter_blue_plus does active scanning
        // so this will arrive alongside the primary advertisement.
        val scanResponseBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)

        if (payload != null && payload.isNotEmpty()) {
            val trimmed = payload.take(MAX_MANUFACTURER_BYTES).toByteArray()
            scanResponseBuilder.addManufacturerData(VEXT_MANUFACTURER_ID, trimmed)
        }

        val scanResponse = scanResponseBuilder.build()

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                isAdvertising = true
                // result.success is called from here; do NOT call result after this.
                result.success(true)
            }

            override fun onStartFailure(errorCode: Int) {
                isAdvertising = false
                activeCallback = null
                val reason = when (errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE          -> "Advertise data too large"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS    -> "Too many advertisers"
                    ADVERTISE_FAILED_ALREADY_STARTED         -> "Already started"
                    ADVERTISE_FAILED_INTERNAL_ERROR          -> "Internal BLE error"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED     -> "BLE advertising not supported"
                    else                                     -> "Unknown error $errorCode"
                }
                result.error("ADVERTISE_FAILED", reason, errorCode)
            }
        }

        activeCallback = callback

        try {
            advertiser.startAdvertising(settings, primaryData, scanResponse, callback)
        } catch (e: SecurityException) {
            // BLUETOOTH_ADVERTISE permission not granted at runtime.
            result.error("PERMISSION_DENIED", "BLUETOOTH_ADVERTISE permission required", null)
        } catch (e: Exception) {
            result.error("ADVERTISE_EXCEPTION", e.message ?: "Unknown exception", null)
        }
    }

    private fun stopAdvertising(result: Result) {
        stopAdvertisingInternal()
        result.success(true)
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    /**
     * Stops advertising without touching the Flutter result — safe to call
     * internally before re-starting, or from MainActivity on destroy.
     */
    fun stopAdvertisingInternal() {
        val cb = activeCallback ?: return
        try {
            leAdvertiser?.stopAdvertising(cb)
        } catch (e: Exception) {
            // Ignore — e.g. adapter already off.
        } finally {
            isAdvertising = false
            activeCallback = null
        }
    }
}
