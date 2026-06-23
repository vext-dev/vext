// ── PublicKeyDirectoryServiceProvider ─────────────────────────────────────────
//
// Simple Provider (not FutureProvider) — construction is synchronous, the
// service does its own async I/O per-call. Mirrors how other Firestore-only
// services in this codebase default to FirebaseFirestore.instance.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/public_key_directory_service.dart';

final publicKeyDirectoryServiceProvider =
    Provider<PublicKeyDirectoryService>((ref) {
  return PublicKeyDirectoryService();
});
