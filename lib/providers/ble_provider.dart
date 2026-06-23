// ── BLE Providers ─────────────────────────────────────────────────────────────
//
// Milestone 1: stub BleStateNotifier.
// Milestone 2: wired real BleTransportLayer.
// Milestone 3 (post-debug): exposed advertisingActive + advertisingError so the
//   UI can warn the user when BLUETOOTH_ADVERTISE permission is denied.
// Milestone 5+ (mode lock): BLE duty cycle is now service-driven, not UI-driven.
//   Services (AttendanceService, SosService, relay nodes) acquire and release
//   priority locks. The effective mode = highest active lock. Tab navigation
//   sets a UI preference but never overrides a service lock — so visiting the
//   Profile tab while a session is broadcasting no longer drops BLE to idle.
//
//   Priority order (highest wins): sosMode > activeSession > uiPreference
//
//   Lock API:
//     acquireSosLock / releaseSosLock   — SOS originator + relay nodes
//     acquireSessionLock / releaseSessionLock — attendance session
//     setUiPreference(MeshMode)         — tab navigation (lowest priority)
//
//   • bleTransportLayerProvider  — the BLE engine singleton
//   • bleStateProvider           — reactive state (active, mode, peerCount,
//                                  advertisingActive, advertisingError)
//   • bleActiveProvider          — convenience bool for AppBar indicator
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ble_transport_layer.dart';
import '../services/mesh_foreground_service.dart';

// ── MeshMode enum ─────────────────────────────────────────────────────────────

/// High-level mode exposed to the UI. Maps 1:1 to BleTransportLayer.ScanDutyMode.
/// Priority order (highest wins): sosMode > activeSession > idle.
enum MeshMode { idle, activeSession, sosMode }

// ── BleState ──────────────────────────────────────────────────────────────────

/// Immutable snapshot of BLE mesh status shown across the UI.
class BleState {
  const BleState({
    this.isActive = false,
    this.mode = MeshMode.idle,
    this.peerCount = 0,
    this.advertisingActive = false,
    this.advertisingError = '',
  });

  final bool isActive;
  final MeshMode mode;
  final int peerCount;

  /// True when the Kotlin BleAdvertiser has confirmed advertising started.
  /// False before start() is called, or when BLUETOOTH_ADVERTISE was denied.
  final bool advertisingActive;

  /// Non-empty when advertising failed — human-readable error for the UI.
  /// Empty when advertisingActive = true (success) or before start() is called.
  final String advertisingError;

  BleState copyWith({
    bool? isActive,
    MeshMode? mode,
    int? peerCount,
    bool? advertisingActive,
    String? advertisingError,
  }) {
    return BleState(
      isActive: isActive ?? this.isActive,
      mode: mode ?? this.mode,
      peerCount: peerCount ?? this.peerCount,
      advertisingActive: advertisingActive ?? this.advertisingActive,
      advertisingError: advertisingError ?? this.advertisingError,
    );
  }
}

// ── BleStateNotifier ──────────────────────────────────────────────────────────

class BleStateNotifier extends StateNotifier<BleState> {
  BleStateNotifier(this._transport) : super(const BleState()) {
    _transport.onPeerCountChanged = (count) {
      state = state.copyWith(peerCount: count);
      MeshForegroundService.updateNotification(count);
    };

    _transport.onAdvertisingStateChanged = (isAdvertising, error) {
      state = state.copyWith(
        advertisingActive: isAdvertising,
        advertisingError: error,
      );
    };
  }

  final BleTransportLayer _transport;

  // ── Mode lock counters ─────────────────────────────────────────────────────
  //
  // Reference-counted locks. Each lock acquisition increments the counter;
  // each release decrements (clamped to 0). The effective duty cycle =
  // highest-priority lock that is currently held.
  //
  // Why counts instead of booleans:
  //   Relay nodes acquire a SOS lock each time an SOS packet is received
  //   (with a 60-second auto-release timer). Multiple packets may arrive before
  //   the first timer fires, so we need a count to correctly balance
  //   acquire/release pairs without resetting all locks on the first release.

  int _sosLockCount = 0;
  int _sessionLockCount = 0;

  // UI preference — lowest priority. Set by tab navigation.
  // Never overrides an active service lock.
  MeshMode _uiPreference = MeshMode.activeSession; // default: session when logged in

  // ── Effective mode ─────────────────────────────────────────────────────────

  /// The actual duty cycle that should be running, based on all active locks.
  MeshMode get _effectiveMode {
    if (_sosLockCount > 0) return MeshMode.sosMode;
    if (_sessionLockCount > 0) return MeshMode.activeSession;
    return _uiPreference;
  }

  // ── Lock API — used by services ────────────────────────────────────────────

  /// Acquire an SOS-mode lock. BLE immediately boosts to 100ms/100ms.
  ///
  /// Called by:
  ///   • SosService when the originator triggers SOS.
  ///   • MeshService relay boost when an SOS packet is received (relay nodes).
  ///
  /// Each call must be paired with [releaseSosLock] to avoid permanent boost.
  Future<void> acquireSosLock() async {
    _sosLockCount++;
    debugPrint('[BLE] SOS lock acquired — count=$_sosLockCount');
    await _applyEffectiveMode();
  }

  /// Release one SOS-mode lock. If count reaches zero, reverts to the next
  /// highest priority (session lock or UI preference).
  Future<void> releaseSosLock() async {
    _sosLockCount = math.max(0, _sosLockCount - 1);
    debugPrint('[BLE] SOS lock released — count=$_sosLockCount');
    await _applyEffectiveMode();
  }

  /// Acquire a session-mode lock. BLE holds at 500ms/500ms minimum.
  ///
  /// Called by AttendanceService when a teacher starts a session.
  /// Students' BLE stays at session rate for the duration of the class.
  Future<void> acquireSessionLock() async {
    _sessionLockCount++;
    debugPrint('[BLE] Session lock acquired — count=$_sessionLockCount');
    await _applyEffectiveMode();
  }

  /// Release one session-mode lock. If count reaches zero, reverts to UI
  /// preference (idle when on Profile tab, session on active lanes).
  Future<void> releaseSessionLock() async {
    _sessionLockCount = math.max(0, _sessionLockCount - 1);
    debugPrint('[BLE] Session lock released — count=$_sessionLockCount');
    await _applyEffectiveMode();
  }

  /// Set the UI preference (called by tab navigation in home_shell.dart).
  ///
  /// This is the LOWEST priority input — it only takes effect when no
  /// service locks are held. It never overrides an active session or SOS lock.
  ///
  /// Replaces the old pattern of calling startIdle/startSession directly from
  /// the shell, which would override service locks.
  Future<void> setUiPreference(MeshMode preference) async {
    _uiPreference = preference;
    await _applyEffectiveMode();
  }

  // ── Private — apply effective mode to transport ────────────────────────────

  /// Compute the effective mode and apply it to the BLE transport.
  ///
  /// If BLE is not yet running, starts it. If already running, updates the
  /// duty cycle. Updates the public [BleState] to reflect the new mode.
  Future<void> _applyEffectiveMode() async {
    final mode = _effectiveMode;

    // Early return if BLE is already active in the correct mode.
    //
    // WHY THIS MATTERS: _applyEffectiveMode is called on every lock change
    // AND every setUiPreference call. setUiPreference is called on every tab
    // tap in home_shell._applyDutyCycleForTab. Without this guard:
    //   - User taps Attendance (session mode) → _transport.start(session) →
    //     _restartDutyCycle() cancels the active scan and starts a fresh one.
    //   - User taps Social (also session mode) → same restart, same disruption.
    // Each restart introduces a ~100ms gap in scanning — minor per-tap but
    // cumulative and visible in BLE packet delivery timing.
    //
    // With the guard: if the effective mode hasn't changed and BLE is already
    // active, skip the transport call entirely. No duty cycle disruption.
    // The guard only applies when BLE is already running (isActive = true).
    // On first start (isActive = false), always proceed to spin up the transport.
    if (state.isActive && state.mode == mode) {
      return; // Already running at the correct rate — nothing to do.
    }

    final dutyMode = switch (mode) {
      MeshMode.sosMode       => ScanDutyMode.sos,
      MeshMode.activeSession => ScanDutyMode.session,
      MeshMode.idle          => ScanDutyMode.idle,
    };

    await _transport.start(mode: dutyMode);
    state = state.copyWith(isActive: true, mode: mode);
    MeshForegroundService.start().ignore();

    debugPrint('[BLE] Mode changed → $mode '
        '(sos=$_sosLockCount session=$_sessionLockCount ui=$_uiPreference)');
  }

  // ── Start / stop — public API (kept for backward compat + direct use) ──────

  /// Set UI preference to idle. Does NOT override active service locks.
  ///
  /// Previously called directly to drop BLE to 1s/30s. Now routes through
  /// the lock system so an active attendance session or SOS always wins.
  Future<void> startIdle() => setUiPreference(MeshMode.idle);

  /// Set UI preference to session. Starts BLE if not running.
  Future<void> startSession() => setUiPreference(MeshMode.activeSession);

  /// Acquire a SOS lock (convenience alias used by SOS callbacks).
  Future<void> startSos() => acquireSosLock();

  /// Stop all BLE activity and clear all locks.
  ///
  /// Call this on logout only. All service locks are reset to zero so
  /// a new login starts with a clean slate.
  Future<void> stopScanning() async {
    _sosLockCount = 0;
    _sessionLockCount = 0;
    _uiPreference = MeshMode.activeSession;

    await _transport.stop();
    MeshForegroundService.stop().ignore();
    state = state.copyWith(
      isActive: false,
      mode: MeshMode.idle,
      peerCount: 0,
      advertisingActive: false,
      advertisingError: '',
    );
    debugPrint('[BLE] All locks cleared, transport stopped.');
  }

  // ── Compatibility stubs ────────────────────────────────────────────────────

  void setActive(bool active) => state = state.copyWith(isActive: active);
  void setMode(MeshMode mode) => state = state.copyWith(mode: mode);
  void updatePeerCount(int count) => state = state.copyWith(peerCount: count);
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// The BLE transport layer singleton. Created eagerly.
final bleTransportLayerProvider = Provider<BleTransportLayer>((ref) {
  final transport = BleTransportLayer();
  ref.onDispose(() => transport.dispose());
  return transport;
});

/// Full BLE mesh state — isActive, mode, peerCount, advertisingActive, error.
final bleStateProvider =
    StateNotifierProvider<BleStateNotifier, BleState>((ref) {
  final transport = ref.watch(bleTransportLayerProvider);
  return BleStateNotifier(transport);
});

/// Convenience bool — true when BLE scanning is active.
final bleActiveProvider = Provider<bool>((ref) {
  return ref.watch(bleStateProvider).isActive;
});
