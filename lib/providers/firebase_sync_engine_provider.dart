// ── FirebaseSyncEngineProvider ────────────────────────────────────────────────
//
// FutureProvider because it depends on AppDatabase (also a FutureProvider).
// The engine is initialised (connectivity listener started) as soon as the DB
// is ready.
//
// Usage (force a manual sync from any widget):
//   final syncAsync = ref.watch(firebaseSyncEngineProvider);
//   syncAsync.whenData((engine) => engine.syncNow());
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_sync_engine.dart';
import 'database_provider.dart';

final firebaseSyncEngineProvider =
    FutureProvider<FirebaseSyncEngine>((ref) async {
  final db = await ref.watch(databaseProvider.future);

  final engine = FirebaseSyncEngine(db: db);
  await engine.initialize();

  ref.onDispose(engine.dispose);

  return engine;
});
