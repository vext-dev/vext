// ── BLE Providers ─────────────────────────────────────────────────────────────
//
// Milestone 1 had a stub BleStateNotifier with no real BLE operations.
// Milestone 2 wires the real BleTransportLayer:
//   • bleTransportLayerProvider  — the BLE scanning/advertising engine
//   • bleStateProvider           — reactive state (active, mode, peerCount)
//   • bleActiveProvider          — convenience bool for AppBar indicator
//
// The BleTransportLayer is created once and lives for the app lifetime.
// Its callbacks push state updates into BleStateNotifier.
// MeshService (Milestone 3) will sit between BleTransportLayer and the DB.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ble_transport_layer.dart';

// ── MeshMode enum ─────────────────────────────────────────────────────────────

/// High-level mode exposed to the UI.
/// Maps 1:1 to BleTransportLayer's ScanDutyMode but lives here so UI code
/// does not import the service layer directly.
enum MeshMode { idle, activeSession, sosMode }

// ── BleState ──────────────────────────────────────────────────────────────────

/// Immutable snapshot of BLE mesh status shown across the UI.
class BleState {
  const BleState({
    this.isActive = false,
    this.mode = MeshMode.idle,
    this.peerCount = 0,
  });

  final bool isActive;
  final MeshMode mode;
  final int peerCount;

  BleState copyWith({bool? isActive, MeshMode? mode, int? peerCount}) {
    return BleState(
      isActive: isActive ?? this.isActive,
      mode: mode ?? this.mode,
      peerCount: peerCount ?? this.peerCount,
    );
  }
}

// ── BleStateNotifier ──────────────────────────────────────────────────────────

class BleStateNotifier extends StateNotifier<BleState> {
  BleStateNotifier(this._transport) : super(const BleState()) {
    // Wire transport layer callbacks → state updates.
    _transport.onPeerCountChanged = (count) {
      state = state.copyWith(peerCount: count);
    };
  }

  final BleTransportLayer _transport;

  // ── Start / stop scanning ──────────────────────────────────────────────────

  /// Begin BLE scanning in idle duty-cycle mode (3% — battery-friendly).
  /// Call this when the app enters the foreground.
  Future<void> startIdle() async {
    await _transport.start(mode: ScanDutyMode.idle);
    state = state.copyWith(isActive: true, mode: MeshMode.idle);
  }

  /// Switch to active session mode (50% duty cycle) — called by AttendanceScreen.
  Future<void> startSession() async {
    await _transport.start(mode: ScanDutyMode.session);
    state = state.copyWith(isActive: true, mode: MeshMode.activeSession);
  }

  /// Switch to SOS mode (near-continuous scanning) — called by SosScreen.
  Future<void> startSos() async {
    await _transport.start(mode: ScanDutyMode.sos);
    state = state.copyWith(isActive: true, mode: MeshMode.sosMode);
  }

  /// Stop scanning and return to idle UI state.
  Future<void> stopScanning() async {
    await _transport.stop();
    state = state.copyWith(isActive: false, mode: MeshMode.idle, peerCount: 0);
  }

  // ── Direct state setters (kept for compatibility with stub screens) ─────────

  void setActive(bool active) {
    state = state.copyWith(isActive: active);
  }

  void setMode(MeshMode mode) {
    state = state.copyWith(mode: mode);
  }

  void updatePeerCount(int count) {
    state = state.copyWith(peerCount: count);
  }

  // NOTE: _transport lifecycle is owned by bleTransportLayerProvider (onDispose).
  // Do NOT call _transport.dispose() here — it would double-dispose.
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// The BLE transport layer singleton.
/// Created eagerly so BLE scanning can start without awaiting the DB.
final bleTransportLayerProvider = Provider<BleTransportLayer>((ref) {
  final transport = BleTransportLayer();
  // dispose() is async — wrap in a closure so Riverpod's void onDispose is satisfied.
  ref.onDispose(() => transport.dispose());
  return transport;
});

/// Full BLE mesh state — isActive, mode, peerCount.
final bleStateProvider =
    StateNotifierProvider<BleStateNotifier, BleState>((ref) {
  final transport = ref.watch(bleTransportLayerProvider);
  return BleStateNotifier(transport);
});

/// Convenience bool — true when BLE scanning is active.
/// Used by the AppBar BLE status indicator.
final bleActiveProvider = Provider<bool>((ref) {
  return ref.watch(bleStateProvider).isActive;
});
