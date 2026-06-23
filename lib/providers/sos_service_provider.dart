// ── SosServiceProvider — VEXT Lane C ──────────────────────────────────────────
//
// FutureProvider because SosService depends on:
//   • MeshService        (FutureProvider — needs DB to be open)
//   • AppDatabase        (FutureProvider — SQLite file open)
//   • FirebaseSyncEngine (FutureProvider — depends on DB)
//   • current Firebase UID (from firebaseUidProvider)
//
// Pattern mirrors attendanceServiceProvider exactly:
//   • Watches firebaseUidProvider (NOT authStateProvider) so the service is
//     only destroyed/recreated on real login/logout events, not on every
//     Firestore snapshot. An active SOS must survive a Firestore write.
//   • All async dependencies are awaited in order after the UID watch.
//   • ref.onDispose() cancels all timers and stream subscriptions cleanly.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lanes/sos/sos_service.dart';
import 'auth_service_provider.dart';
import 'ble_provider.dart';
import 'database_provider.dart';
import 'firebase_sync_engine_provider.dart';
import 'mesh_service_provider.dart';

final sosServiceProvider = FutureProvider<SosService>((ref) async {
  // ── UID — from firebaseUidProvider, NOT authStateProvider ─────────────────
  // Registered synchronously before any awaits so invalidation is caught
  // correctly even if the user logs out while awaits are in flight.
  final uid = ref.watch(firebaseUidProvider).valueOrNull;

  if (uid == null || uid.isEmpty) {
    throw StateError('sosServiceProvider: user is not authenticated');
  }

  // ── Wait for all async dependencies ───────────────────────────────────────
  final mesh       = await ref.watch(meshServiceProvider.future);
  final db         = await ref.watch(databaseProvider.future);
  final syncEngine = await ref.watch(firebaseSyncEngineProvider.future);

  // ── BLE duty cycle callbacks ───────────────────────────────────────────────
  // Injected via constructor so SosService has no Riverpod dependency.
  // onSosActivated  → boosts BLE scan to 100ms/100ms (SOS mode) on trigger.
  // onSosCancelled  → reverts to 500ms/500ms (session mode) on cancel.
  // ref.read (not ref.watch) — bleStateNotifier is a stable singleton;
  // we don't want provider recreation to cascade from BLE state changes.
  final bleNotifier = ref.read(bleStateProvider.notifier);

  final service = SosService(
    mesh: mesh,
    db: db,
    syncEngine: syncEngine,
    currentUserUid: uid,
    // acquireSosLock: boosts BLE to 100ms/100ms immediately.
    // releaseSosLock: reverts to the next highest lock (session or UI pref).
    // This replaces the old startSos/startSession pattern which always
    // dropped to session mode on cancel regardless of prior state.
    onSosActivated: () => bleNotifier.acquireSosLock(),
    onSosCancelled: () => bleNotifier.releaseSosLock(),
  );

  service.initialize();

  ref.onDispose(() => service.dispose().ignore());

  return service;
});

// ── IncomingSos list provider ─────────────────────────────────────────────────
//
// Holds the ordered list of incoming SOS alerts received since app start.
// Lives at PROVIDER level — never tied to screen lifecycle.
//
// KEY INVARIANT: alerts received while the SOS tab is not open are NOT lost.
// Previously _incoming was widget state: if SosScreen was unmounted when a
// packet arrived, the stream event fired into the void. Now the subscription
// lives here, always active, and SosScreen simply reads the accumulated list.
//
// The notifier re-subscribes automatically if sosServiceProvider is recreated
// (e.g. after logout/login) because ref.listen fires on every new value.

class IncomingSosNotifier extends StateNotifier<List<IncomingSos>> {
  IncomingSosNotifier() : super(const []);

  StreamSubscription<IncomingSos>? _sub;

  /// Attach to a new [SosService]. Safe to call again — cancels the old
  /// subscription first so we never double-count alerts.
  ///
  /// IMPORTANT: state is cleared on re-subscription so a new user session
  /// never inherits the previous session's incoming SOS list.
  void subscribeToService(SosService svc) {
    _sub?.cancel();
    state = const []; // ← clear previous session's alerts before new session
    _sub = svc.incomingSosStream.listen(_onIncoming);
  }

  void _onIncoming(IncomingSos incoming) {
    final updated = [incoming, ...state];
    // Cap at 50 entries to avoid unbounded memory growth.
    state = updated.length > 50 ? updated.sublist(0, 50) : updated;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Accumulated list of all incoming SOS alerts since app start.
/// Persists across tab navigation — use this instead of widget-local state.
final incomingSosProvider =
    StateNotifierProvider<IncomingSosNotifier, List<IncomingSos>>((ref) {
  final notifier = IncomingSosNotifier();

  // TWO-PART subscription (avoids fireImmediately — not universally supported
  // across Riverpod 2.x patch versions):
  //
  // Part 1 — ref.read: subscribes immediately if sosServiceProvider is ALREADY
  //   resolved at the time this provider is first created. This covers the common
  //   case where the user is already logged in when the provider scope initialises.
  ref.read(sosServiceProvider).whenData(notifier.subscribeToService);

  // Part 2 — ref.listen: fires whenever the provider value CHANGES — i.e. when
  //   the service transitions from loading → data (first login), or when it is
  //   recreated after logout/login. Together with Part 1, all cases are covered.
  ref.listen<AsyncValue<SosService>>(
    sosServiceProvider,
    (_, next) => next.whenData(notifier.subscribeToService),
  );

  return notifier;
});
