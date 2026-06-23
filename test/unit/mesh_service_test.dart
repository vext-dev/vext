// ── MeshService Unit Tests ─────────────────────────────────────────────────────
//
// Covers the gossip relay engine without any BLE platform channels.
//
// Strategy:
//   _FakeBleTransport  — BleTransportLayer subclass; overrides broadcastPacket
//                        to record relayed bytes without touching platform channels.
//   AppDatabase.memory() — real in-memory SQLite; no mocking needed.
//
// Packet reception is simulated by calling transport.onPacketReceived!(packet, rssi)
// directly, which is exactly what the real BLE layer does.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vext/core/proto/mesh_packet.dart';
import 'package:vext/services/ble_transport_layer.dart';
import 'package:vext/services/drift_service.dart';
import 'package:vext/services/mesh_service.dart';

// ── Fake transport — captures broadcasts, no platform channel calls ────────────

class _FakeBleTransport extends BleTransportLayer {
  final List<List<int>> broadcasts = [];

  @override
  void broadcastPacket(
    List<int> packetBytes, {
    bool requireAck = false,
    bool retryOnAllFailure = false,
  }) {
    broadcasts.add(List<int>.from(packetBytes));
  }
}

// ── Packet factories ───────────────────────────────────────────────────────────

MeshPacket _sos({required String id, int ttl = 3}) => MeshPacket.sos(
      id: id,
      senderUid: 'uid-teacher-1',
      latitude: 12.9716,
      longitude: 77.5946,
      ttl: ttl,
    );

MeshPacket _attendance({required String id, int ttl = 5}) =>
    MeshPacket.attendance(
      id: id,
      senderUid: 'uid-teacher-1',
      sessionId: 'session-abc',
      hmacToken: 'deadbeef',
      ttl: ttl,
    );

MeshPacket _message({required String id, int ttl = 7}) => MeshPacket.message(
      id: id,
      senderUid: 'uid-student-1',
      contentEncrypted: 'hello campus',
      ttl: ttl,
    );

MeshPacket _ack({required String id}) => MeshPacket(
      id: id,
      type: PacketType.ack,
      ttl: 3,
      senderUid: 'uid-gateway',
      timestamp: DateTime.now(),
    );

MeshPacket _advertisementHeader({required String id}) => MeshPacket(
      id: id,
      type: PacketType.sos,
      ttl: 3,
      senderUid: '', // advertisement-only: no senderUid
      timestamp: DateTime.now(),
    );

// Drain the event queue far enough for relay to complete.
//
// Sequence when a packet arrives:
//   [microtask] DB hasSeenPacket completes → _handleIncomingPacket resumes
//   [microtask] DB markPacketSeen completes → _scheduleRelay called → T_relay registered
//   [timer turn 1] test's own Future.delayed(zero) fires first (registered earlier)
//   [timer turn 2] T_relay fires → broadcastPacket called
//
// Two timer turns are therefore needed: the first clears the microtask queue
// (allowing T_relay to be registered), the second lets T_relay actually fire.
Future<void> _pump() async {
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  late _FakeBleTransport transport;
  late AppDatabase db;
  late MeshService mesh;

  setUp(() async {
    transport = _FakeBleTransport();
    db = AppDatabase.memory();
    mesh = MeshService(transport: transport, db: db);
    await mesh.initialize();
  });

  tearDown(() async {
    mesh.dispose();
    await db.close();
  });

  // ── Lane dispatch ────────────────────────────────────────────────────────────

  group('Lane dispatch', () {
    test('SOS packet → sosPackets stream', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000001');

      expectLater(
        mesh.sosPackets,
        emitsThrough(predicate<MeshPacket>((e) => e.id == p.id)),
      );

      transport.onPacketReceived!(p, -70);
      await _pump();
    });

    test('attendance packet → attendancePackets stream', () async {
      final p = _attendance(id: 'a0000000-0000-0000-0000-000000000002');

      expectLater(
        mesh.attendancePackets,
        emitsThrough(predicate<MeshPacket>((e) => e.id == p.id)),
      );

      transport.onPacketReceived!(p, -70);
      await _pump();
    });

    test('message packet → messagePackets stream', () async {
      final p = _message(id: 'a0000000-0000-0000-0000-000000000003');

      expectLater(
        mesh.messagePackets,
        emitsThrough(predicate<MeshPacket>((e) => e.id == p.id)),
      );

      transport.onPacketReceived!(p, -70);
      await _pump();
    });

    test('ack packet → ackPackets stream', () async {
      final p = _ack(id: 'a0000000-0000-0000-0000-000000000004');

      expectLater(
        mesh.ackPackets,
        emitsThrough(predicate<MeshPacket>((e) => e.id == p.id)),
      );

      transport.onPacketReceived!(p, -70);
      await _pump();
    });

    test('advertisement-only packet (senderUid empty) not dispatched', () async {
      final p = _advertisementHeader(id: 'a0000000-0000-0000-0000-000000000005');
      final received = <MeshPacket>[];
      final sub = mesh.sosPackets.listen(received.add);

      transport.onPacketReceived!(p, -70);
      await _pump();
      await _pump(); // two pumps to be safe

      await sub.cancel();
      expect(received, isEmpty,
          reason: 'advertisement-only packets must not reach lane streams');
    });
  });

  // ── Deduplication ────────────────────────────────────────────────────────────

  group('Deduplication', () {
    test('same packet received twice is dispatched only once', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000006');
      final received = <MeshPacket>[];
      final sub = mesh.sosPackets.listen(received.add);

      transport.onPacketReceived!(p, -70);
      await _pump();
      transport.onPacketReceived!(p, -70); // duplicate
      await _pump();

      await sub.cancel();
      expect(received.length, 1,
          reason: 'duplicate packet must be dropped by SeenPackets dedup');
    });

    test('sendPacket marks packet seen — not relayed if received back', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000007');
      await mesh.sendPacket(p);

      final received = <MeshPacket>[];
      final sub = mesh.sosPackets.listen(received.add);

      // Simulate the packet echoing back from a peer.
      transport.onPacketReceived!(p, -70);
      await _pump();

      await sub.cancel();
      expect(received, isEmpty,
          reason: 'packets originated here must not be re-dispatched');
    });
  });

  // ── Relay — TTL management ───────────────────────────────────────────────────

  group('Relay — TTL', () {
    test('SOS packet TTL=2 is relayed with TTL=1', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000008', ttl: 2);
      transport.onPacketReceived!(p, -70);

      // SOS relay delay = Duration.zero → fires on next event-loop turn.
      await _pump();

      expect(transport.broadcasts, isNotEmpty,
          reason: 'packet with TTL=2 must be relayed');
      final relayed =
          MeshPacket.fromBytes(Uint8List.fromList(transport.broadcasts.last));
      expect(relayed, isNotNull);
      expect(relayed!.id, p.id, reason: 'relayed packet must have same UUID');
      expect(relayed.ttl, 1, reason: 'relay must decrement TTL by 1');
    });

    test('SOS packet TTL=1 is NOT relayed (decremented to 0 = expired)', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000009', ttl: 1);
      transport.onPacketReceived!(p, -70);
      await _pump();

      expect(transport.broadcasts, isEmpty,
          reason: 'packet that would expire after decrement must not be relayed');
    });

    test('packet with TTL=0 is never scheduled for relay', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000010', ttl: 0);
      transport.onPacketReceived!(p, -70);
      await _pump();

      expect(transport.broadcasts, isEmpty,
          reason: 'already-expired packet must never be relayed');
    });

    test('relayed packet carries correct type and senderUid', () async {
      final p = _sos(id: 'a0000000-0000-0000-0000-000000000011', ttl: 5);
      transport.onPacketReceived!(p, -70);
      await _pump();

      expect(transport.broadcasts, isNotEmpty);
      final relayed =
          MeshPacket.fromBytes(Uint8List.fromList(transport.broadcasts.last));
      expect(relayed!.type, PacketType.sos);
      expect(relayed.senderUid, 'uid-teacher-1');
    });
  });

  // ── Multiple distinct packets ─────────────────────────────────────────────────

  group('Multiple packets', () {
    test('two distinct packets are both dispatched', () async {
      final p1 = _sos(id: 'a0000000-0000-0000-0000-000000000012');
      final p2 = _sos(id: 'a0000000-0000-0000-0000-000000000013');
      final received = <String>[];
      final sub = mesh.sosPackets.listen((p) => received.add(p.id));

      transport.onPacketReceived!(p1, -70);
      await _pump();
      transport.onPacketReceived!(p2, -70);
      await _pump();

      await sub.cancel();
      expect(received, containsAll([p1.id, p2.id]));
    });
  });
}
