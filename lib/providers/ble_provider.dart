// ── BLE Providers ─────────────────────────────────────────────────────────────
//
// Milestone 1: stub BleStateNotifier.
// Milestone 2: wired real BleTransportLayer.
// Milestone 3 (post-debug): exposed advertisingActive + advertisingError so the
//   UI can warn the user when BLUETOOTH_ADVERTISE permission is denied.
//
//   • bleTransportLayerProvider  — the BLE engine singleton
//   • bleStateProvider           — reactive state (active, mode, peerCount,
//                                  advertisingActive, advertisingError)
//   • bleActiveProvider          — convenience bool for AppBar indicator
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ble_transport_layer.dart';

// ── MeshMode enum ─────────────────────────────────────────────────────────────

/// High-level mode exposed to the UI. Maps 1:1 to BleTransportLayer.ScanDutyMode.
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
    // Wire transport callbacks → state updates.
    _transport.onPeerCountChanged = (count) {
      state = state.copyWith(peerCount: count);
    };

    // Advertising state: fires after every startAdvertising() attempt.
    // isAdvertising=true → confirmed running. false + error → needs user action.
    _transport.onAdvertisingStateChanged = (isAdvertising, error) {
      state = state.copyWith(
        advertisingActive: isAdvertising,
        advertisingError: error,
      );
    };
  }

  final BleTransportLayer _transport;

  // ── Start / stop ───────────────────────────────────────────────────────────

  /// Idle duty cycle (3%). Use for passive mesh participation.
  Future<void> startIdle() async {
    await _transport.start(mode: ScanDutyMode.idle);
    state = state.copyWith(isActive: true, mode: MeshMode.idle);
  }

  /// Session duty cycle (50%). Use when attendance or social screen is active.
  Future<void> startSession() async {
    await _transport.start(mode: ScanDutyMode.session);
    state = state.copyWith(isActive: true, mode: MeshMode.activeSession);
  }

  /// SOS duty cycle (near-continuous). Use when SOS is triggered.
  Future<void> startSos() async {
    await _transport.start(mode: ScanDutyMode.sos);
    state = state.copyWith(isActive: true, mode: MeshMode.sosMode);
  }

  /// Stop scanning and advertising. Resets to idle UI state.
  Future<void> stopScanning() async {
    await _transport.stop();
    state = state.copyWith(
      isActive: false,
      mode: MeshMode.idle,
      peerCount: 0,
      advertisingActive: false,
      advertisingError: '',
    );
  }

  // ── Compatibility setters (kept for stub screens) ──────────────────────────

  void setActive(bool active) {
    state = state.copyWith(isActive: active);
  }

  void setMode(MeshMode mode) {
    state = state.copyWith(mode: mode);
  }

  void updatePeerCount(int count) {
    state = state.copyWith(peerCount: count);
  }
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
