// ── MeshServiceProvider ───────────────────────────────────────────────────────
//
// FutureProvider because MeshService depends on AppDatabase (also a
// FutureProvider). The mesh engine is not available until the DB file is open.
//
// Usage in a widget:
//   final meshAsync = ref.watch(meshServiceProvider);
//   meshAsync.whenData((mesh) {
//     mesh.sosPackets.listen((packet) { ... });
//   });
//
// Usage outside widgets (e.g. in a background service callback):
//   final mesh = ref.read(meshServiceProvider).requireValue;
//   await mesh.sendPacket(packet);
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/mesh_service.dart';
import 'ble_provider.dart';
import 'database_provider.dart';

final meshServiceProvider = FutureProvider<MeshService>((ref) async {
  // Wait for the database to be ready before initialising MeshService.
  final db = await ref.watch(databaseProvider.future);

  // BleTransportLayer is a synchronous Provider — always available.
  final transport = ref.watch(bleTransportLayerProvider);

  final service = MeshService(transport: transport, db: db);
  await service.initialize();

  // Dispose mesh engine when the provider scope tears down (tests, hot-restart).
  ref.onDispose(service.dispose);

  return service;
});
