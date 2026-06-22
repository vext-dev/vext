// ── MeshServiceProvider ───────────────────────────────────────────────────────
//
// FutureProvider because MeshService depends on AppDatabase (also a
// FutureProvider). The mesh engine is not available until the DB file is open.
//
// Relay SOS boost:
//   When any node receives an SOS packet, mesh_service fires onSosPacketReceived.
//   This provider wires that callback to BleStateNotifier.acquireSosLock so the
//   relay node immediately boosts its BLE scan to 100ms/100ms — without this,
//   relay nodes stay in idle mode (30s sleep) and multi-hop SOS takes 30+ seconds
//   per hop to reach the next phone.
//
//   The lock is auto-released after 60 seconds of no new SOS packets. If another
//   SOS packet arrives before the timer fires, the timer is reset (extending the
//   boost window). A single boolean flag ensures we don't stack multiple locks —
//   one acquire/release pair regardless of how many packets arrive.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/mesh_service.dart';
import 'ble_provider.dart';
import 'database_provider.dart';

final meshServiceProvider = FutureProvider<MeshService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final transport = ref.watch(bleTransportLayerProvider);
  final bleNotifier = ref.read(bleStateProvider.notifier);

  final service = MeshService(transport: transport, db: db);
  await service.initialize();

  // ── Relay SOS duty boost ───────────────────────────────────────────────────
  // Track relay boost state with a flag + debounce timer so we don't stack
  // multiple acquireSosLock calls from rapid consecutive SOS packets.
  bool relayBoostActive = false;
  Timer? relayBoostTimer;

  service.onSosPacketReceived = () {
    // Acquire the lock only on the FIRST packet (not on every relay hop).
    if (!relayBoostActive) {
      relayBoostActive = true;
      bleNotifier.acquireSosLock().ignore();
    }
    // Reset/extend the 60-second release window on every packet.
    // This keeps relay nodes in SOS mode for as long as SOS traffic is flowing.
    relayBoostTimer?.cancel();
    relayBoostTimer = Timer(const Duration(seconds: 60), () {
      relayBoostActive = false;
      relayBoostTimer = null;
      bleNotifier.releaseSosLock().ignore();
    });
  };

  ref.onDispose(() {
    relayBoostTimer?.cancel();
    // If a relay boost is still active when the provider disposes (logout),
    // release the lock so the next session starts clean.
    if (relayBoostActive) {
      bleNotifier.releaseSosLock().ignore();
      relayBoostActive = false;
    }
    service.dispose();
  });

  return service;
});
