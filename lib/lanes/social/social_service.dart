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
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_constants.dart';
import '../../core/proto/mesh_packet.dart';
import '../../services/crypto_service.dart';
import '../../services/drift_service.dart';
import '../../services/firebase_sync_engine.dart';
import '../../services/mesh_service.dart';
import '../../services/public_key_directory_service.dart';

class SocialService {
  SocialService({
    required MeshService mesh,
    required AppDatabase db,
    required FirebaseSyncEngine syncEngine,
    required String currentUserUid,
    required CryptoService crypto,
    required PublicKeyDirectoryService publicKeyDirectory,
    FirebaseFirestore? firestore,
  })  : _mesh = mesh,
        _db = db,
        _syncEngine = syncEngine,
        _currentUserUid = currentUserUid,
        _crypto = crypto,
        _publicKeyDirectory = publicKeyDirectory,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final MeshService _mesh;
  final AppDatabase _db;
  final FirebaseSyncEngine _syncEngine;
  final String _currentUserUid;
  final CryptoService _crypto;
  final PublicKeyDirectoryService _publicKeyDirectory;
  final FirebaseFirestore _firestore;

  // ── Dedup ──────────────────────────────────────────────────────────────────
  //
  // Caps at _dedupeMaxSize entries with FIFO eviction — mirrors SosService.
  //
  // WHY A CAP: SocialService is alive for the entire authenticated session
  // (only disposed on logout). Over a full campus day with hundreds of
  // messages, an uncapped Set grows indefinitely. Each UUID is ~36 bytes;
  // 10 000 entries ≈ 360 KB plus Set overhead. The cap bounds memory to
  // ~18 KB (500 × 36 B) regardless of session length.
  //
  // WHY FIFO: oldest IDs are the least likely to be re-delivered — BLE mesh
  // dedup windows are short (60-minute SeenPackets TTL in Drift). Evicting
  // the oldest entry is therefore the correct policy: a re-delivered ancient
  // packet would be dropped by the DB's insertOnConflictUpdate anyway (same
  // primary key), so the Set-level dedup missing it causes at most a harmless
  // no-op DB write, not a duplicate in the UI.
  static const _dedupeMaxSize = 500;
  final Set<String> _processedPacketIds = {};
  final List<String> _processedPacketOrder = []; // insertion-order for eviction

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<MeshPacket>? _packetSub;

  // Firestore snapshot listener for messages from devices NOT in BLE range.
  // Subscribes to messages/broadcast/records — the same path that
  // FirebaseSyncEngine._syncMessages() writes to (threadId = 'broadcast').
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;

  // Mesh stream of 1:1 direct messages (Milestone 7).
  StreamSubscription<MeshPacket>? _directMessageSub;

  // Firestore collectionGroup listener for DMs addressed to this device that
  // arrived via a path with no BLE link (e.g. another building, WiFi-only).
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreDmSub;

  // ── Public: live message list ──────────────────────────────────────────────

  /// Live stream of all BROADCAST [MessageRecord] rows, ordered newest-first.
  ///
  /// Backed by Drift's [watch] — emits immediately on every insert.
  /// SocialScreen consumes this stream to render the chat list without any
  /// additional polling or manual refresh. Direct messages are excluded —
  /// see [directMessageStream] for 1:1 threads.
  Stream<List<MessageRecord>> get messageStream => _db.watchAllMessages();

  /// Live stream of a single 1:1 DM thread with [peerUid], ordered
  /// newest-first. Used by DirectMessageScreen.
  Stream<List<MessageRecord>> directMessageStream(String peerUid) =>
      _db.watchDirectMessages(_currentUserUid, peerUid);

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

    // ── Direct messages (Milestone 7) ─────────────────────────────────────────

    // Upload our own X25519 public key so peers can DM us. Fire-and-forget:
    // failure here just means peers can't reach this device with a DM until
    // the next successful attempt (e.g. next app start) — not fatal to any
    // other lane, so it must never block initialize().
    _crypto.getX25519PublicKeyBytes().then((bytes) {
      return _publicKeyDirectory.uploadOwnPublicKey(
        uid: _currentUserUid,
        publicKeyBytes: bytes,
      );
    }).catchError((e) {
      debugPrint('[Social] Failed to upload public key: $e');
    });

    _directMessageSub = _mesh.directMessagePackets.listen(_onDirectMessagePacket);

    // Firestore receive path for DMs, mirroring the broadcast listener above
    // but scoped to documents addressed to this user across ALL thread
    // subcollections via a collectionGroup query (threadId varies per DM
    // pair — see FirebaseSyncEngine._syncMessages — so we can't subscribe to
    // a single known path the way the broadcast listener does).
    //
    // Requires a composite index (recipientUid ASC, timestamp ASC,
    // COLLECTION_GROUP scope on 'records') — see firestore.indexes.json.
    final dmSince = Timestamp.fromDate(DateTime.now());
    _firestoreDmSub = _firestore
        .collectionGroup(AppConstants.fsRecords)
        .where('recipientUid', isEqualTo: _currentUserUid)
        .where('timestamp', isGreaterThanOrEqualTo: dmSince)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen(_onFirestoreDmSnapshot, onError: (e) {
      debugPrint('[Social] Firestore DM snapshot error: $e');
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
    _markProcessed(msgId);

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

  /// Send a 1:1 encrypted direct message to [recipientUid].
  ///
  /// Throws [StateError] if [recipientUid] has not yet uploaded an X25519
  /// public key (e.g. never opened the app since Milestone 7 shipped) —
  /// callers (DirectMessageScreen) should surface this as a user-facing
  /// "can't message this person yet" error, not a silent failure.
  ///
  /// Encrypts with CryptoService.encryptMessage (X25519 ECDH + AES-256-GCM),
  /// sends the ciphertext over the mesh as a PacketType.directMessage packet,
  /// and persists locally with the PLAINTEXT we just composed in
  /// contentEncrypted (so the UI renders it with zero decrypt step — see
  /// MessageRecords.contentEncrypted's doc comment in tables.dart) alongside
  /// the real ciphertext in cipherBlob for FirebaseSyncEngine to mirror.
  Future<void> sendDirectMessage(String recipientUid, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final recipientKey = await _publicKeyDirectory.getPublicKey(recipientUid);
    if (recipientKey == null) {
      throw StateError(
        'Cannot send: recipient has not set up encryption yet.',
      );
    }

    final encrypted = await _crypto.encryptMessage(trimmed, recipientKey);
    final cipherBytes = encrypted.toBytes();

    final msgId = const Uuid().v4();
    final now = DateTime.now();

    final packet = MeshPacket.directMessage(
      id: msgId,
      senderUid: _currentUserUid,
      recipientUid: recipientUid,
      encryptedBytes: cipherBytes,
      ttl: AppConstants.ttlMessage,
    );

    // Mark as processed so we don't echo our own send back to the chat.
    _markProcessed(msgId);

    // ── Send over mesh ───────────────────────────────────────────────────────
    await _mesh.sendPacket(packet);

    // ── Persist locally (triggers directMessageStream) ───────────────────────
    await _db.upsertMessage(MessageRecordsCompanion(
      id: Value(msgId),
      senderUid: Value(_currentUserUid),
      contentEncrypted: Value(trimmed),
      ttl: Value(AppConstants.ttlMessage),
      timestamp: Value(now),
      lane: const Value('social'),
      synced: const Value(false),
      isRead: const Value(true), // Own messages are always "read"
      recipientUid: Value(recipientUid),
      cipherBlob: Value(base64Encode(cipherBytes)),
    ));

    // ── Sync to Firestore (best-effort, non-blocking) ─────────────────────────
    _syncEngine.syncNow().ignore();
  }

  /// Search the campus roster by display name (case-insensitive, substring
  /// match). Used by the DM "search by name" entry point — no username
  /// field exists in this schema, so display name is the only practical
  /// search basis (decided over tap-only entry, since not every conversation
  /// starts from a visible broadcast message).
  ///
  /// Bounded client-side filter over a single read of the users collection:
  /// Firestore has no native case-insensitive search, and this app targets
  /// a single institution's roster (hundreds, not millions, of users) — an
  /// acceptable read-cost tradeoff at this scale. Revisit with a dedicated
  /// search index (Algolia/Typesense) if this ever needs to scale beyond
  /// one institution.
  Future<List<({String uid, String name})>> searchUsersByName(
    String query,
  ) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return [];

    final snapshot = await _firestore.collection(AppConstants.fsUsers).get();
    final results = <({String uid, String name})>[];
    for (final doc in snapshot.docs) {
      if (doc.id == _currentUserUid) continue; // can't DM yourself
      final name = (doc.data()['name'] as String?)?.trim() ?? '';
      if (name.toLowerCase().contains(needle)) {
        results.add((uid: doc.id, name: name));
      }
    }
    return results;
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _packetSub?.cancel();
    await _firestoreSub?.cancel();
    await _directMessageSub?.cancel();
    await _firestoreDmSub?.cancel();
    _processedPacketIds.clear();
    _processedPacketOrder.clear();
  }

  // ── Private — dedup helper ─────────────────────────────────────────────────

  /// Mark [id] as processed. Evicts the oldest entry when the cap is reached
  /// (FIFO via [_processedPacketOrder]) so memory stays bounded across long
  /// sessions. Returns true if the id was NOT previously seen (caller should
  /// process it); false if it was already seen (caller should skip it).
  bool _markProcessed(String id) {
    if (_processedPacketIds.contains(id)) return false;
    if (_processedPacketIds.length >= _dedupeMaxSize) {
      final oldest = _processedPacketOrder.removeAt(0);
      _processedPacketIds.remove(oldest);
    }
    _processedPacketIds.add(id);
    _processedPacketOrder.add(id);
    return true;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Handle an incoming message packet from the mesh.
  void _onMessagePacket(MeshPacket packet) {
    // Ignore our own messages (echoed back from GATT relay path).
    if (packet.senderUid == _currentUserUid) return;

    // Deduplicate — mesh relay can deliver the same packet multiple times.
    if (!_markProcessed(packet.id)) return;

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

  /// Handle an incoming direct-message packet from the mesh.
  ///
  /// Relay nodes see EVERY directMessage packet in transit, addressed to
  /// peers they may not be — they must forward (handled generically by
  /// MeshService._scheduleRelay, unrelated to this method) WITHOUT attempting
  /// to decrypt anything not addressed to them. This gate is the
  /// confidentiality boundary: only a packet whose recipientUid matches our
  /// own UID proceeds to decryption.
  void _onDirectMessagePacket(MeshPacket packet) {
    if (packet.senderUid == _currentUserUid) return; // our own send, echoed

    final decoded = packet.decodeDirectMessagePayload();
    if (decoded == null) return;

    // Not addressed to this device — we're just relaying it. Do NOT decrypt.
    if (decoded.recipientUid != _currentUserUid) return;

    // Deduplicate — mesh relay can deliver the same packet multiple times.
    if (!_markProcessed(packet.id)) return;

    _decryptAndStoreDirectMessage(
      msgId: packet.id,
      senderUid: packet.senderUid,
      recipientUid: decoded.recipientUid,
      encryptedBytes: decoded.encryptedBytes,
      timestamp: packet.timestamp,
      ttl: packet.ttl,
      markSynced: false,
    ).ignore();
  }

  /// Shared by both receive paths (BLE mesh and Firestore collectionGroup):
  /// looks up the sender's X25519 public key, decrypts via ECDH + AES-256-GCM
  /// (CryptoService.decryptMessage), and persists the result. Silently drops
  /// the message (with a debug log) on missing key or auth failure — both are
  /// recoverable on the NEXT delivery attempt (mesh retry / Firestore resync),
  /// so there's no good user-facing action to take on a single failed attempt.
  Future<void> _decryptAndStoreDirectMessage({
    required String msgId,
    required String senderUid,
    required String recipientUid,
    required Uint8List encryptedBytes,
    required DateTime timestamp,
    required int ttl,
    required bool markSynced,
  }) async {
    final encrypted = EncryptedMessage.fromBytes(encryptedBytes);
    if (encrypted == null) {
      debugPrint('[Social] DM $msgId from $senderUid: malformed ciphertext');
      return;
    }

    final senderKey = await _publicKeyDirectory.getPublicKey(senderUid);
    if (senderKey == null) {
      debugPrint(
        '[Social] DM $msgId from $senderUid: no public key on file, cannot decrypt',
      );
      return;
    }

    String plaintext;
    try {
      plaintext = await _crypto.decryptMessage(encrypted, senderKey);
    } catch (e) {
      debugPrint('[Social] DM $msgId from $senderUid: decrypt failed — $e');
      return;
    }

    await _db.upsertMessage(MessageRecordsCompanion(
      id: Value(msgId),
      senderUid: Value(senderUid),
      contentEncrypted: Value(plaintext),
      ttl: Value(ttl),
      timestamp: Value(timestamp),
      lane: const Value('social'),
      synced: Value(markSynced),
      isRead: const Value(false),
      recipientUid: Value(recipientUid),
      cipherBlob: Value(base64Encode(encryptedBytes)),
    ));

    if (!markSynced) {
      _syncEngine.syncNow().ignore();
    }
  }

  /// Handle a Firestore collectionGroup snapshot of DMs addressed to us.
  ///
  /// Unlike the broadcast path, the Firestore 'contentEncrypted' field for a
  /// DM document holds base64 CIPHERTEXT (FirebaseSyncEngine never uploads DM
  /// plaintext) — decode and decrypt it here, mirroring
  /// _decryptAndStoreDirectMessage's BLE counterpart.
  void _onFirestoreDmSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;

      final data = change.doc.data();
      if (data == null) continue;

      final id = data['id'] as String?;
      final senderUid = data['senderUid'] as String?;
      final recipientUid = data['recipientUid'] as String?;
      final cipherB64 = data['contentEncrypted'] as String?;
      final ttl = (data['ttl'] as num?)?.toInt();
      final tsRaw = data['timestamp'];

      if (id == null ||
          senderUid == null ||
          recipientUid == null ||
          cipherB64 == null ||
          ttl == null ||
          tsRaw == null) {
        continue;
      }

      // Our own DM, already stored locally at send time.
      if (senderUid == _currentUserUid) continue;

      // Deduplicate — might have already arrived via BLE mesh.
      if (!_markProcessed(id)) continue;

      final timestamp = tsRaw is Timestamp ? tsRaw.toDate() : DateTime.now();

      debugPrint('[Social] Firestore DM from $senderUid');

      _decryptAndStoreDirectMessage(
        msgId: id,
        senderUid: senderUid,
        recipientUid: recipientUid,
        encryptedBytes: Uint8List.fromList(base64Decode(cipherB64)),
        timestamp: timestamp,
        ttl: ttl,
        markSynced: true, // Already in Firestore.
      ).ignore();
    }
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
          ttl == null || tsRaw == null) {
        continue;
      }

      // Deduplicate — might have already arrived via BLE mesh.
      if (!_markProcessed(id)) continue;

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
