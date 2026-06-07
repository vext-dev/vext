package com.example.vext

// ── VextAlarmReceiver — AlarmManager deep-Doze BLE scan restarter ──────────────
//
// Purpose:
//   Android's deep Doze mode suspends the Dart event loop, causing the
//   BleTransportLayer duty-cycle timer to stall silently. The WakeLock (Fix 1A)
//   handles normal background sleep, but deep Doze is a stronger power mode
//   that ignores WakeLocks for network and defers most work.
//
//   AlarmManager.setExactAndAllowWhileIdle() is the ONLY API guaranteed to fire
//   during deep Doze. This receiver wakes up on that alarm, pushes a "scanRestart"
//   event to the Dart EventChannel, and BleTransportLayer restarts its duty-cycle
//   timer from Dart.
//
// Flow:
//   BleTransportLayer.start() → scheduleDozeAlarm(intervalMs) via MethodChannel
//     → MainActivity schedules alarm → deep Doze hits → alarm fires
//     → VextAlarmReceiver.onReceive() → eventSink.success("scanRestart")
//     → BleTransportLayer._onAlarmEvent() → _restartDutyCycle() + reschedule
//
// Thread safety:
//   eventSink is @Volatile so reads/writes from the main thread (onReceive)
//   and the Flutter platform thread (stream handler attach/detach) are visible
//   to each other without needing a lock.
//
// Why a companion object for eventSink?
//   BroadcastReceivers are instantiated fresh for each onReceive() call — there
//   is no persistent instance to hold the sink. The companion object acts as
//   a process-scoped singleton that MainActivity populates when Dart subscribes.
//
// ──────────────────────────────────────────────────────────────────────────────

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.EventChannel

class VextAlarmReceiver : BroadcastReceiver() {

    companion object {
        /// Broadcast action string — must match the Intent created in MainActivity.
        const val ACTION = "com.example.vext.DOZE_SCAN_RESTART"

        /// PendingIntent request code — arbitrary, but must be unique per alarm.
        const val REQUEST_CODE = 0xBEEF

        /**
         * Set by MainActivity's EventChannel StreamHandler when Dart subscribes.
         * Cleared (set to null) when Dart cancels the subscription (BLE stopped).
         *
         * @Volatile ensures the write from the platform thread (onListen/onCancel)
         * is immediately visible to the main thread (onReceive). This is sufficient
         * synchronisation — we never read-modify-write, only assign.
         */
        @Volatile
        var eventSink: EventChannel.EventSink? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return

        // Push a "scanRestart" string to the Dart stream.
        // BleTransportLayer's _alarmEventsChannel listener calls _restartDutyCycle()
        // and immediately reschedules the next alarm via scheduleDozeAlarm().
        //
        // If eventSink is null (process was killed and restarted, or BLE was stopped
        // before the alarm fired), this is a no-op — the next BLE start() call will
        // schedule a fresh alarm anyway.
        eventSink?.success("scanRestart")
    }
}
