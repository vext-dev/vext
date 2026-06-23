// ── SocialServiceProvider — VEXT Lane B ───────────────────────────────────────
//
// FutureProvider<SocialService> — pattern mirrors sosServiceProvider exactly:
//   • Watches firebaseUidProvider (NOT authStateProvider) so the service is
//     only destroyed/recreated on real login/logout events, not on every
//     Firestore snapshot write.
//   • All async dependencies are awaited after the UID watch.
//   • ref.onDispose() cancels stream subscriptions and clears state cleanly.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lanes/social/social_service.dart';
import 'auth_service_provider.dart';
import 'crypto_service_provider.dart';
import 'database_provider.dart';
import 'firebase_sync_engine_provider.dart';
import 'mesh_service_provider.dart';
import 'public_key_directory_service_provider.dart';

final socialServiceProvider = FutureProvider<SocialService>((ref) async {
  // ── UID — registered before any awaits so invalidation is caught correctly
  final uid = ref.watch(firebaseUidProvider).valueOrNull;

  if (uid == null || uid.isEmpty) {
    throw StateError('socialServiceProvider: user is not authenticated');
  }

  // ── Wait for all async dependencies ───────────────────────────────────────
  final mesh       = await ref.watch(meshServiceProvider.future);
  final db         = await ref.watch(databaseProvider.future);
  final syncEngine = await ref.watch(firebaseSyncEngineProvider.future);
  final crypto     = await ref.watch(cryptoServiceProvider.future);
  final publicKeyDirectory = ref.watch(publicKeyDirectoryServiceProvider);

  final service = SocialService(
    mesh: mesh,
    db: db,
    syncEngine: syncEngine,
    currentUserUid: uid,
    crypto: crypto,
    publicKeyDirectory: publicKeyDirectory,
  );

  service.initialize();

  ref.onDispose(() => service.dispose().ignore());

  return service;
});
