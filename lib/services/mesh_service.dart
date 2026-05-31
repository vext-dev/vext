// ── MeshService — VEXT Gossip Mesh Engine ──────────────────────────────────────
//
// Sits between BleTransportLayer (raw BLE bytes) and the three feature lanes
// (Attendance, Social, SOS). Implements the gossip-relay protocol.
//
// Responsibilities:
//   • Deduplication via SeenPackets table (60-minute TTL).
//   • TTL management — decrement on relay, discard at 0.
//   • Lane dispatch — routes packets to typed broadcast streams.
//   • Relay with adaptive backoff:
//       SOS     → immediate (0 ms delay)
//       Others  → random 50–500 ms (reduces broadcast storms)
//   • Advertisement — keeps this node discoverable with a "heartbeat" packet.
//   • Periodic DB maintenance (every 30 min).
//
// Usage:
//   final mesh = MeshService(transport: transport, db: db);
//   await mesh.initialize();
//
//   // Subscribe to a lane:
//   mesh.attendancePackets.listen((packet) { ... });
//   mesh.sosPackets.listen((packet) { ... });
//
//   // Send a packet originating from this device:
//   await mesh.sendPacket(packet);
//
//   // Cleanup:
//   mesh.dispose();
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import '../core/app_constants.dart';
import '../core/proto/mesh_packet.dart';
import '../services/ble_transport_layer.dart';
import '../services/drift_service.dart';

// ── AttendanceAdvertisement ────────────────────────────────────────────────────
//
// Wraps an advertisement-only attendance packet with its measured RSSI.
// Advertisement-only packets (senderUid == '') carry only type+ttl+uuid — they
// have no sessionId/hmacToken payload. However their RSSI from the BLE scan
// provides the proximity evidence required for attendance proof assembly.
//
// In the M4 flow:
//   • Teacher calls transport.advertisePacket() → Kotlin BleAdvertiser broadcasts
//     the attendance packet's 18-byte header on the VEXT service UUID.
//   • Student's scanner picks up the advertisement with real RSSI.
//   • AttendanceService reads RSSI from this stream for proximity verification.
//   • Full payload (sessionId + hmacToken) arrives separately via GATT on the
//     attendancePackets stream (MeshPacket with senderUid != '').
//
class AttendanceAdvertisement {
  const AttendanceAdvertisement({required this.packet, required this.rssi});

  /// The 18-byte advertisement header parsed into a MeshPacket.
  /// senderUid is '' (unknown until GATT fetch). type == PacketType.attendance.
  final MeshPacket packet;

  /// RSSI measured by the local scanner at time of advertisement receipt.
  /// Negative integer (e.g. -65 dBm). Use AppConstants.rssiThresholdDefault (-75)
  /// as the minimum to accept for attendance.
  final int rssi;
}

class MeshService {
  MeshService({
    required BleTransportLayer transport,
    required AppDatabase db,
  })  : _transport = transport,
        _db = db;

  final BleTransportLayer _transport;
  final AppDatabase _db;
  final _random = math.Random();

  // ── Lane dispatch streams ──────────────────────────────────────────────────

  /// Attendance announcement packets (Lane A) — originated by teacher nodes.
  final _attendanceController =
      StreamController<MeshPacket>.broadcast();

  /// Social message packets (Lane B) — E2E encrypted in Milestone 6.
  final _messageController =
      StreamController<MeshPacket>.broadcast();

  /// SOS emergency packets (Lane C) — unencrypted, TTL=255, zero-delay relay.
  final _sosController =
      StreamController<MeshPacket>.broadcast();

  /// ACK packets — SOS gateway confirmation, or message delivery receipt.
  final _ackController =
      StreamController<MeshPacket>.broadcast();

  /// Attendance advertisement-only packets with their BLE RSSI value.
  /// These are the 18-byte advertisement headers scanned from the air —
  /// they contain NO payload but carry real proximity data (RSSI).
  /// AttendanceService subscribes to this alongside attendancePackets.
  final _attendanceAdvController =
      StreamController<AttendanceAdvertisement>.broadcast();

  Stream<MeshPacket> get attendancePackets => _attendanceController.stream;
  Stream<MeshPacket> get messagePackets    => _messageController.stream;
  Stream<MeshPacket> get sosPackets        => _sosController.stream;
  Stream<MeshPacket> get ackPackets        => _ackController.stream;

  /// Attendance BLE advertisement stream — carries real RSSI for proximity proof.
  /// Emits whenever the scanner receives a peer advertising PacketType.attendance.
  Stream<AttendanceAdvertisement> get attendanceAdvertisements =>
      _attendanceAdvController.stream;

  // ── Internal state ─────────────────────────────────────────────────────────

  bool _initialized = false;
  Timer? _maintenanceTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Wire callbacks and start periodic maintenance.
  /// Must be called once before using any lane streams or [sendPacket].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Wire the single incoming-packet callback. This is called for BOTH
    // advertisement-header packets (senderUid == '') and full GATT packets.
    // Use a lambda wrapper so the async future is explicitly ignored at the
    // call site — avoids unawaited_futures lint on the void callback typedef.
    _transport.onPacketReceived = (packet, rssi) {
      _handleIncomingPacket(packet, rssi).ignore();
    };

    // DB maintenance: purge old SeenPackets, Messages, Peers every 30 minutes.
    _maintenanceTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _db.runMaintenance(),
    );
  }

  /// Stop all mesh activity and close stream controllers.
  void dispose() {
    _transport.onPacketReceived = null;
    _maintenanceTimer?.cancel();
    _attendanceController.close();
    _messageController.close();
    _sosController.close();
    _ackController.close();
    _attendanceAdvController.close();
    _initialized = false;
  }

  // ── Outbound — send a packet originated on this device ────────────────────

  /// Broadcast [packet] to all currently visible peers via GATT.
  /// Also records the packet as seen locally (so we don't relay our own packets).
  Future<void> sendPacket(MeshPacket packet) async {
    // Mark as seen so we don't relay our own origination.
    await _db.markPacketSeen(packet.id);
    _transport.broadcastPacket(packet.toBytes());
  }

  // ── Inbound — handle packets arriving from the BLE layer ──────────────────

  /// Central packet handler — called by BleTransportLayer for both
  /// advertisement-header packets and full GATT packets.
  Future<void> _handleIncomingPacket(MeshPacket packet, int rssi) async {
    // ── 1. Deduplication ──────────────────────────────────────────────────
    // Drop packets already processed to prevent relay loops.
    final alreadySeen = await _db.hasSeenPacket(packet.id);
    if (alreadySeen) return;

    await _db.markPacketSeen(packet.id);

    // ── 2. Advertisement-only packet (18-byte header, no payload) ─────────
    // These come from BLE advertisement service data. They carry only
    // type + ttl + uuid — no senderUid, no payload.
    //
    // Special case for Milestone 4 (Lane A):
    //   Attendance advertisements are forwarded to attendanceAdvertisements
    //   stream WITH their RSSI so AttendanceService can use real proximity data.
    //   All other advertisement-only types are still dropped here (no useful
    //   payload to process without a GATT fetch).
    if (packet.senderUid.isEmpty) {
      if (packet.type == PacketType.attendance) {
        _attendanceAdvController.add(
          AttendanceAdvertisement(packet: packet, rssi: rssi),
        );
      }
      return;
    }

    // ── 3. Full GATT packet — lane dispatch ───────────────────────────────
    switch (packet.type) {
      case PacketType.attendance:
        _attendanceController.add(packet);

      case PacketType.message:
        _messageController.add(packet);

      case PacketType.sos:
        _sosController.add(packet);

      case PacketType.ack:
        _ackController.add(packet);
    }

    // ── 4. Relay — forward if TTL still allows ────────────────────────────
    if (!packet.isExpired) {
      _scheduleRelay(packet);
    }
  }

  // ── Relay logic ────────────────────────────────────────────────────────────

  /// Schedule a relay of [packet] with appropriate backoff.
  ///
  /// SOS uses zero delay — every millisecond matters in an emergency.
  /// All other types use a random 50–500 ms window to stagger relays
  /// from multiple nodes that received the same packet simultaneously
  /// (reduces GATT collision probability).
  void _scheduleRelay(MeshPacket packet) {
    final delay = packet.type == PacketType.sos
        ? Duration.zero
        : Duration(
            milliseconds: AppConstants.backoffBaseMs +
                _random.nextInt(
                  AppConstants.backoffMaxMs - AppConstants.backoffBaseMs,
                ),
          );

    Future.delayed(delay, () {
      if (!_initialized) return;

      final relayed = packet.decrementTtl();
      if (relayed.isExpired) return;

      // Fire-and-forget — GATT errors are handled inside broadcastPacket.
      _transport.broadcastPacket(relayed.toBytes());
    });
  }
}
