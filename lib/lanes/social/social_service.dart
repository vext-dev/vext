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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
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
    FirebaseFirestore? firestore,
  })  : _mesh = mesh,
        _db = db,
        _syncEngine = syncEngine,
        _currentUserUid = currentUserUid,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final MeshService _mesh;
  final AppDatabase _db;
  final FirebaseSyncEngine _syncEngine;
  final String _currentUserUid;
  final FirebaseFirestore _firestore;

  // ── Dedup ──────────────────────────────────────────────────────────────────
  final Set<String> _processedPacketIds = {};

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<MeshPacket>? _packetSub;

  // Firestore snapshot listener for messages from devices NOT in BLE range.
  // Subscribes to messages/broadcast/records — the same path that
  // FirebaseSyncEngine._syncMessages() writes to (threadId = 'broadcast').
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;

  // ── Public: live message list ──────────────────────────────────────────────

  /// Live stream of all [MessageRecord] rows, ordered newest-first.
  ///
  /// Backed by Drift's [watch] — emits immediately on every insert.
  /// SocialScreen consumes this stream to render the chat list without any
  /// additional polling or manual refresh.
  Stream<List<MessageRecord>> get messageStream => _db.watchAllMessages();

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Wire the mesh message stream and Firestore receive path.
  /// Call once after construction.
  void initialize() {
    _packetSub = _mesh.messagePackets.listen(_onMessagePacket);

    // ── Firestore receive path (BUG C4 fix) ──────────────────────────────────
    // Subscribes to messages from devices NOT currently in BLE range — e.g.
    // a message sent from another building that reached Firestore via WiFi.
    // Only messages with a timestamp AFTER service init are fetched so we
    // don't flood the screen with historical messages on every app start.
    //
    // The listener fires for ALL documents in the collection (including our
    // own outgoing messages that just synced) — _processedPacketIds deduplicates
    // them so own-messages never appear twice.
    final since = Timestamp.fromDate(DateTime.now());
    _firestoreSub = _firestore
        .collection(AppConstants.fsMessages)
        .doc('broadcast')
        .collection(AppConstants.fsRecords)
        .where('timestamp', isGreaterThanOrEqualTo: since)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen(_onFirestoreSnapshot, onError: (e) {
      debugPrint('[Social] Firestore snapshot error: $e');
    });
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
    await _firestoreSub?.cancel();
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

  /// Handle a Firestore snapshot from the 'broadcast' thread.
  ///
  /// Fires for both added and modified documents. We only care about new
  /// messages (DocumentChangeType.added). The dedup set prevents messages
  /// already received via BLE mesh from appearing twice.
  void _onFirestoreSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;

      final data = change.doc.data();
      if (data == null) continue;

      final id = data['id'] as String?;
      final senderUid = data['senderUid'] as String?;
      final content = data['contentEncrypted'] as String?;
      final ttl = (data['ttl'] as num?)?.toInt();
      final tsRaw = data['timestamp'];

      if (id == null || senderUid == null || content == null ||
          ttl == null || tsRaw == null) continue;

      // Deduplicate — might have already arrived via BLE mesh.
      if (_processedPacketIds.contains(id)) continue;
      _processedPacketIds.add(id);

      // Ignore our own messages echoed back from Firestore.
      if (senderUid == _currentUserUid) continue;

      final timestamp = tsRaw is Timestamp
          ? tsRaw.toDate()
          : DateTime.now();

      debugPrint('[Social] Firestore message from $senderUid');

      _db.upsertMessage(MessageRecordsCompanion(
        id: Value(id),
        senderUid: Value(senderUid),
        contentEncrypted: Value(content),
        ttl: Value(ttl),
        timestamp: Value(timestamp),
        lane: const Value('social'),
        synced: const Value(true), // Already in Firestore — mark synced.
        isRead: const Value(false),
      )).ignore();
    }
  }
}
