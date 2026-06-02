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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lanes/sos/sos_service.dart';
import 'auth_service_provider.dart';
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

  final service = SosService(
    mesh: mesh,
    db: db,
    syncEngine: syncEngine,
    currentUserUid: uid,
  );

  service.initialize();

  ref.onDispose(() => service.dispose().ignore());

  return service;
});
