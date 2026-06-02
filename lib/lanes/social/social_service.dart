// ── SocialService — VEXT Lane B Social Mesh Chat ──────────────────────────────
//
// Manages social message send/receive for ALL roles.
//
// ── Send flow ─────────────────────────────────────────────────────────────────
//   1. sendMessage(content) →
//        - Builds MeshPacket.message(id, senderUid, contentEncrypted).
//        - Calls mesh.sendPacket() — immediate BLE GATT delivery to peers.
//        - Writes MessageRecord to Drift with synced=false.
//        - Calls syncEngine.syncNow() (optional cloud backup — M6 demo path).
//        - Local Drift write triggers messageStream to emit the updated list.
//
// ── Receive flow ──────────────────────────────────────────────────────────────
//   1. Listens to mesh.messagePackets broadcast stream.
//   2. When a packet arrives from ANOTHER node:
//        - Deduplicates via _processedPacketIds (in-memory) + Drift primary key
//          (insertOnConflictUpdate is a no-op for duplicates).
//        - Decodes UTF-8 content via packet.decodeMessageContent().
//        - Writes MessageRecord to Drift — triggers messageStream automatically.
//        - Calls syncEngine.syncNow() for cloud backup (best-effort).
//
// ── messageStream ──────────────────────────────────────────────────────────────
//   Returns a live Drift watch stream (List<MessageRecord>, newest-first).
//   The SocialScreen subscribes to this — the list updates automatically on
//   every insert without any manual StreamController wiring.
//
// ── Pattern ────────────────────────────────────────────────────────────────────
//   Mirrors SosService / AttendanceService exactly:
//   - FutureProvider provider (see social_service_provider.dart)
//   - ref.watch(firebaseUidProvider) ← NOT authStateProvider
//   - ref.onDispose() → service.dispose()
//   - No direct BleTransportLayer access — only through MeshService.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/app_constants.dart';
import '../../core/proto/mesh_packet.dart';
import '../../services/drift_service.dart';
import '../../services/firebase_sync_engine.dart';
import '../../services/mesh_service.dart';

class SocialService {
  SocialService({
    required MeshService mesh,
    required AppDatabase db,
    required FirebaseSyncEngine syncEngine,
    required String currentUserUid,
  })  : _mesh = mesh,
        _db = db,
        _syncEngine = syncEngine,
        _currentUserUid = currentUserUid;

  final MeshService _mesh;
  final AppDatabase _db;
  final FirebaseSyncEngine _syncEngine;
  final String _currentUserUid;

  // ── Dedup ──────────────────────────────────────────────────────────────────
  final Set<String> _processedPacketIds = {};

  // ── Subscription ──────────────────────────────────────────────────────────
  StreamSubscription<MeshPacket>? _packetSub;

  // ── Public: live message list ──────────────────────────────────────────────

  /// Live stream of all [MessageRecord] rows, ordered newest-first.
  ///
  /// Backed by Drift's [watch] — emits immediately on every insert.
  /// SocialScreen consumes this stream to render the chat list without any
  /// additional polling or manual refresh.
  Stream<List<MessageRecord>> get messageStream => _db.watchAllMessages();

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Wire the mesh message stream. Call once after construction.
  void initialize() {
    _packetSub = _mesh.messagePackets.listen(_onMessagePacket);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Send a social message to all nearby mesh peers.
  ///
  /// Builds a [MeshPacket.message], sends it immediately, writes it to the
  /// local Drift DB (which updates [messageStream]), and triggers a Firestore
  /// sync for cloud backup. Does NOT block the UI — all DB/sync ops are
  /// fire-and-forget after the mesh send.
  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final msgId = const Uuid().v4();
    final now = DateTime.now();

    final packet = MeshPacket.message(
      id: msgId,
      senderUid: _currentUserUid,
      contentEncrypted: trimmed, // Plaintext in M6; encrypted in M7
      ttl: AppConstants.ttlMessage,
    );

    // Mark as processed so we don't echo our own send back to the chat.
    _processedPacketIds.add(msgId);

    // ── Send over mesh ───────────────────────────────────────────────────────
    await _mesh.sendPacket(packet);

    // ── Persist locally (triggers messageStream) ─────────────────────────────
    await _db.upsertMessage(MessageRecordsCompanion(
      id: Value(msgId),
      senderUid: Value(_currentUserUid),
      contentEncrypted: Value(trimmed),
      ttl: Value(AppConstants.ttlMessage),
      timestamp: Value(now),
      lane: const Value('social'),
      synced: const Value(false),
      isRead: const Value(true), // Own messages are always "read"
    ));

    // ── Sync to Firestore (best-effort, non-blocking) ─────────────────────────
    _syncEngine.syncNow().ignore();
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _packetSub?.cancel();
    _processedPacketIds.clear();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Handle an incoming message packet from the mesh.
  void _onMessagePacket(MeshPacket packet) {
    // Ignore our own messages (echoed back from GATT relay path).
    if (packet.senderUid == _currentUserUid) return;

    // Deduplicate — mesh relay can deliver the same packet multiple times.
    if (_processedPacketIds.contains(packet.id)) return;
    _processedPacketIds.add(packet.id);

    final content = packet.decodeMessageContent();
    if (content == null || content.isEmpty) return;

    // Persist — Drift primary-key upsert is a no-op for duplicates.
    // The insert triggers messageStream to emit an updated list automatically.
    _db.upsertMessage(MessageRecordsCompanion(
      id: Value(packet.id),
      senderUid: Value(packet.senderUid),
      contentEncrypted: Value(content),
      ttl: Value(packet.ttl),
      timestamp: Value(packet.timestamp),
      lane: const Value('social'),
      synced: const Value(false),
      isRead: const Value(false),
    )).ignore();

    // Sync to Firestore — best-effort backup.
    _syncEngine.syncNow().ignore();
  }
}
