// ── CryptoServiceProvider ─────────────────────────────────────────────────────
//
// FutureProvider because CryptoService.initialize() is async (reads from
// flutter_secure_storage which uses Android Keystore I/O).
//
// Usage:
//   final cryptoAsync = ref.watch(cryptoServiceProvider);
//   cryptoAsync.whenData((crypto) async {
//     final token = await crypto.generateHmacToken(sessionId, courseId);
//   });
//
// Or synchronously (only after app has fully loaded — splash guard ensures this):
//   final crypto = ref.read(cryptoServiceProvider).requireValue;
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crypto_service.dart';

final cryptoServiceProvider = FutureProvider<CryptoService>((ref) async {
  final service = CryptoService();
  await service.initialize();
  // No explicit dispose needed — CryptoService holds no streams or timers.
  return service;
});
