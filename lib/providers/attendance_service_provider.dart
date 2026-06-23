// ── AttendanceServiceProvider ─────────────────────────────────────────────────
//
// FutureProvider because AttendanceService depends on:
//   • MeshService  (FutureProvider — needs DB to be open)
//   • AppDatabase  (FutureProvider — SQLite file open)
//   • CryptoService (FutureProvider — Android Keystore I/O)
//   • FirebaseSyncEngine (FutureProvider — depends on DB)
//   • current Firebase UID (from firebaseUidProvider)
//
// IMPORTANT — why firebaseUidProvider and NOT authStateProvider:
//
//   authStateProvider uses Firestore snapshots() internally. It fires on
//   EVERY Firestore document write — role updates, key uploads, proof uploads.
//   If we watch authStateProvider here, this FutureProvider is invalidated on
//   each of those writes, disposing the AttendanceService (cancels broadcast
//   timers, kills mesh subscriptions, clears submitted session IDs) mid-session.
//   A teacher's session would silently stop broadcasting after the first student
//   is marked present (because the proof upload triggers a Firestore snapshot).
//
//   firebaseUidProvider is backed by FirebaseAuth.authStateChanges() only —
//   it fires ONLY on actual login/logout. The service is therefore only
//   destroyed and recreated on real session boundaries.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lanes/attendance/attendance_service.dart';
import 'auth_service_provider.dart';
import 'ble_provider.dart';
import 'crypto_service_provider.dart';
import 'database_provider.dart';
import 'firebase_sync_engine_provider.dart';
import 'mesh_service_provider.dart';

final attendanceServiceProvider =
    FutureProvider<AttendanceService>((ref) async {
  // ── UID — from firebaseUidProvider, NOT authStateProvider ─────────────────
  // firebaseUidProvider only fires on login/logout (Firebase Auth events).
  // This prevents the service from being rebuilt on every Firestore snapshot.
  //
  // Placing this watch BEFORE the awaits ensures the dependency is registered
  // synchronously, so provider invalidation is triggered correctly on logout.
  final uid = ref.watch(firebaseUidProvider).valueOrNull;

  // Guard: if the user is not authenticated (logged out, or auth still
  // loading), throw so the FutureProvider enters error state. Widgets guard
  // against this with attendanceAsync.when(error: ...).
  if (uid == null || uid.isEmpty) {
    throw StateError('attendanceServiceProvider: user is not authenticated');
  }

  // ── Wait for all async dependencies ───────────────────────────────────────
  final mesh       = await ref.watch(meshServiceProvider.future);
  final db         = await ref.watch(databaseProvider.future);
  final crypto     = await ref.watch(cryptoServiceProvider.future);
  final syncEngine = await ref.watch(firebaseSyncEngineProvider.future);

  // BLE session lock callbacks — injected so AttendanceService stays
  // decoupled from Riverpod. ref.read (not ref.watch) — bleStateNotifier is
  // a stable singleton and we don't want provider recreation from BLE changes.
  final bleNotifier = ref.read(bleStateProvider.notifier);

  final service = AttendanceService(
    mesh: mesh,
    db: db,
    crypto: crypto,
    syncEngine: syncEngine,
    currentUserUid: uid,
    onSessionLockAcquired: () => bleNotifier.acquireSessionLock(),
    onSessionLockReleased: () => bleNotifier.releaseSessionLock(),
  );

  service.initialize();

  // Dispose cleans up all timers and stream subscriptions.
  // Wrapped in a closure because service.dispose() is async and
  // ref.onDispose requires a synchronous void callback.
  ref.onDispose(() => service.dispose().ignore());

  return service;
});
