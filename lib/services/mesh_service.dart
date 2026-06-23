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

import 'package:flutter/foundation.dart';

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

  /// 1:1 encrypted direct message packets (Lane B, Milestone 7). Carries
  /// every directMessage packet seen on this node regardless of
  /// recipientUid — SocialService checks whether it's addressed to this
  /// device before attempting to decrypt.
  final _directMessageController =
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
  Stream<MeshPacket> get directMessagePackets =>
      _directMessageController.stream;

  /// Attendance BLE advertisement stream — carries real RSSI for proximity proof.
  /// Emits whenever the scanner receives a peer advertising PacketType.attendance.
  Stream<AttendanceAdvertisement> get attendanceAdvertisements =>
      _attendanceAdvController.stream;

  // ── External callbacks ─────────────────────────────────────────────────────

  /// Called when an SOS packet is received and dispatched (relay nodes only).
  ///
  /// Wire this in mesh_service_provider.dart to BleStateNotifier.acquireSosLock
  /// with a 60-second auto-release timer. This ensures relay nodes boost their
  /// own BLE scan to 100ms/100ms immediately upon receiving an SOS, so they
  /// can discover and relay to their own neighbours faster.
  ///
  /// Without this, relay nodes stay in whatever duty cycle they were in (often
  /// idle = 30s sleep), making multi-hop SOS delivery take 30+ seconds per hop.
  VoidCallback? onSosPacketReceived;

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
  /// Safe to call multiple times — guarded by _initialized flag.
  void dispose() {
    if (!_initialized) return; // already disposed — guard against double-call
    _transport.onPacketReceived = null;
    _maintenanceTimer?.cancel();
    _attendanceController.close();
    _messageController.close();
    _sosController.close();
    _ackController.close();
    _directMessageController.close();
    _attendanceAdvController.close();
    _initialized = false;
  }

  // ── Outbound — send a packet originated on this device ────────────────────

  /// Broadcast [packet] to all currently visible peers via GATT.
  /// Also records the packet as seen locally (so we don't relay our own packets).
  ///
  /// SOS packets use `retryOnAllFailure: true` — if every GATT connection slot
  /// is capped at the moment of broadcast, the packet is queued and retried
  /// every 3 seconds for up to 30 seconds (Fix 2C). Other types rely on their
  /// own re-broadcast timers (attendance: 5 s, social: no retry needed).
  ///
  /// SOS and attendance packets use `requireAck: true` — ATT Write Request
  /// waits for the peer's BLE controller to confirm receipt, making
  /// `sendPacketToPeer` returning `true` mean "peer received it" not just
  /// "local radio queued it". This is the correct semantic for originated
  /// packets where the retry and re-broadcast logic depends on delivery proof.
  /// Relay hops (in _scheduleRelay) do NOT set requireAck so relay throughput
  /// is not degraded by round-trip confirmation overhead.
  Future<void> sendPacket(MeshPacket packet) async {
    await _db.markPacketSeen(packet.id);
    final isCritical = packet.type == PacketType.sos ||
        packet.type == PacketType.attendance ||
        packet.type == PacketType.ack;

    // retryOnAllFailure: true for SOS (safety-critical) AND messages (slow
    // without retry — if _peerDevices is empty on send, the message is silently
    // dropped with no fallback on BLE-only setups). Direct messages get the
    // same treatment as broadcast messages for the same reason.
    // Attendance and ACK re-broadcast is handled by their own timers.
    final needsRetry = packet.type == PacketType.sos ||
        packet.type == PacketType.message ||
        packet.type == PacketType.directMessage;

    _transport.broadcastPacket(
      packet.toBytes(),
      retryOnAllFailure: needsRetry,
      requireAck: isCritical,
    );
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
    // Logged with the [Mesh] tag so a 3-phone relay test can be verified via
    // `adb logcat | grep "\[Mesh\]"` on each device — see
    // VEXT_TESTING_DEMO_GUIDE.md §10 "3-Phone Mesh Relay Verification". An
    // RX line on the middle phone followed by a TX-relay line (below, in
    // _scheduleRelay) for the SAME packet id, followed by an RX line with
    // that id on the far phone, is proof of an actual multi-hop relay rather
    // than two coincidental direct links.
    debugPrint('[Mesh] RX  $packet rssi=$rssi');

    switch (packet.type) {
      case PacketType.attendance:
        _attendanceController.add(packet);

      case PacketType.message:
        _messageController.add(packet);

      case PacketType.sos:
        _sosController.add(packet);
        // Notify the BLE layer so relay nodes boost their own scan rate.
        // This is essential for multi-hop SOS delivery: without this, Phone B
        // receives the SOS from Phone A but can't relay to Phone C because B
        // is in idle mode (30s sleep gap). The boost ensures B scans at 100ms
        // immediately after receiving, so C is discovered within one cycle.
        onSosPacketReceived?.call();

      case PacketType.ack:
        _ackController.add(packet);

      case PacketType.directMessage:
        _directMessageController.add(packet);
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

      // See the matching RX log in _handleIncomingPacket — pair these two
      // lines across devices to prove multi-hop relay during physical testing.
      debugPrint('[Mesh] TX-relay $relayed (received at ttl ${packet.ttl})');

      // SOS relays also use the retry queue — a relay node failing to reach
      // its peers should retry for the same 30-second window (Fix 2C).
      _transport.broadcastPacket(
        relayed.toBytes(),
        retryOnAllFailure: relayed.type == PacketType.sos,
      );
    });
  }
}
