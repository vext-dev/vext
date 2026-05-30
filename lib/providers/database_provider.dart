// ── DatabaseProvider ──────────────────────────────────────────────────────────
//
// Riverpod provider for the AppDatabase singleton.
//
// Usage:
//   final db = ref.watch(databaseProvider);
//   final proofs = await db.unsyncedAttendanceProofs();
//
// The database is opened once per app lifecycle. Riverpod's onDispose
// closes it cleanly when the ProviderScope is disposed (e.g. in tests).
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/drift_service.dart';

/// Async provider that opens the SQLite database on first access.
///
/// Using [FutureProvider] ensures the DB file is ready before any
/// screen tries to query it. Screens watch this with:
///
///   final dbAsync = ref.watch(databaseProvider);
///   dbAsync.when(data: (db) { ... }, loading: ..., error: ...);
///
/// Or, in a screen that can safely assume the DB is ready (after splash):
///
///   final db = ref.watch(databaseProvider).requireValue;
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabase.open();

  // Close the database when the provider is disposed (tests, hot-restart).
  ref.onDispose(db.close);

  return db;
});
