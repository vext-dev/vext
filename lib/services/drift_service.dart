// ── AppDatabase — VEXT VigilantMesh local SQLite store ────────────────────────
//
// Uses Drift (formerly Moor) for type-safe, code-generated SQLite access.
//
// SETUP REQUIRED (run once, and again after schema changes):
//   dart run build_runner build --delete-conflicting-outputs
//
// This generates drift_service.g.dart which contains:
//   • _$AppDatabase mixin  (SQL DDL + insert/query boilerplate)
//   • Row data classes     (AttendanceProof, MessageRecord, SosRecord, etc.)
//   • Companion classes    (used for insert/update with optional fields)
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/tables.dart';

part 'drift_service.g.dart';

// ── Database class ─────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    AttendanceProofs,
    MessageRecords,
    SosRecords,
    SeenPackets,
    Peers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Used by the DatabaseProvider to open the production database.
  /// The database file lives in the app's documents directory —
  /// survives app updates, cleared on uninstall.
  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'vext_mesh.db');
    return AppDatabase(NativeDatabase(File(dbPath)));
  }

  /// Used in unit tests to get an in-memory database (fast, no disk I/O).
  factory AppDatabase.memory() {
    return AppDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 3;

  // ── Migration ────────────────────────────────────────────────────────────────
  //
  // v1 → v2: Added UNIQUE(session_id, student_uid) to attendance_proofs.
  //
  // SQLite cannot add a UNIQUE constraint to an existing column via
  // ALTER TABLE — the table must be recreated. Drift's m.recreateTable()
  // handles this: it creates a temp table with the new schema, copies all
  // rows, drops the old table, then renames the temp table.
  //
  // Before recreating, we deduplicate existing rows by keeping only the
  // most recently inserted row (highest rowid) per (session_id, student_uid)
  // pair. This is safe: the most recent row is the most complete proof.
  //
  // Never rename or drop columns without a migration. Bump schemaVersion
  // for every structural change and add a corresponding onUpgrade branch.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2: Add UNIQUE(session_id, student_uid) to attendance_proofs.
            //
            // m.recreateTable() does not exist in Drift 2.21 — use raw SQLite
            // to manually recreate the table (SQLite cannot ALTER TABLE ADD UNIQUE).
            //
            // Step 1: Deduplicate existing rows (keep most-recently inserted per pair).
            await customStatement('''
              DELETE FROM attendance_proofs
              WHERE rowid NOT IN (
                SELECT MAX(rowid)
                FROM attendance_proofs
                GROUP BY session_id, student_uid
              )
            ''');

            // Step 2: Create a new table with the UNIQUE constraint.
            // Column types match what Drift generates from the AttendanceProofs schema.
            await customStatement('''
              CREATE TABLE IF NOT EXISTS attendance_proofs_new (
                "id"          TEXT NOT NULL PRIMARY KEY,
                "session_id"  TEXT NOT NULL,
                "student_uid" TEXT NOT NULL,
                "hmac_token"  TEXT NOT NULL,
                "rssi"        INTEGER NOT NULL,
                "timestamp"   INTEGER NOT NULL,
                "gps_lat"     REAL,
                "gps_lng"     REAL,
                "synced"      INTEGER NOT NULL DEFAULT 0
                                CHECK ("synced" IN (0, 1)),
                UNIQUE ("session_id", "student_uid")
              )
            ''');

            // Step 3: Copy the clean (deduplicated) rows into the new table.
            await customStatement('''
              INSERT OR IGNORE INTO attendance_proofs_new
                SELECT id, session_id, student_uid, hmac_token,
                       rssi, timestamp, gps_lat, gps_lng, synced
                FROM attendance_proofs
            ''');

            // Step 4: Swap tables.
            await customStatement('DROP TABLE attendance_proofs');
            await customStatement(
              'ALTER TABLE attendance_proofs_new RENAME TO attendance_proofs',
            );
          }

          if (from < 3) {
            // v2 → v3: Add recipientUid + cipherBlob to message_records for
            // 1:1 direct messages (Milestone 7). Both are plain nullable
            // columns with no uniqueness constraint, so — unlike the v1→v2
            // change above — a simple ALTER TABLE ADD COLUMN suffices; no
            // table recreate needed. Existing broadcast rows get NULL in
            // both columns, which the app already treats as "this is a
            // broadcast message" (recipientUid == null).
            await m.addColumn(messageRecords, messageRecords.recipientUid);
            await m.addColumn(messageRecords, messageRecords.cipherBlob);
          }
        },
      );

  // ────────────────────────────────────────────────────────────────────────────
  // DAO: AttendanceProofs
  // ────────────────────────────────────────────────────────────────────────────

  /// Insert a new attendance proof. Silently ignores duplicates (same UUID).
  Future<void> upsertAttendanceProof(AttendanceProofsCompanion proof) {
    return into(attendanceProofs).insertOnConflictUpdate(proof);
  }

  /// All unsynced proofs — called by FirebaseSyncEngine before cloud upload.
  Future<List<AttendanceProof>> unsyncedAttendanceProofs() {
    return (select(attendanceProofs)
          ..where((t) => t.synced.equals(false)))
        .get();
  }

  /// Mark a proof as synced after successful Firestore write.
  Future<void> markAttendanceProofSynced(String id) {
    return (update(attendanceProofs)..where((t) => t.id.equals(id)))
        .write(const AttendanceProofsCompanion(synced: Value(true)));
  }

  /// All proofs for a specific session — used on AttendanceScreen.
  Future<List<AttendanceProof>> proofsForSession(String sessionId) {
    return (select(attendanceProofs)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
  }

  /// Live-updating proof list for [sessionId] — emits on every DB change.
  /// Used by TeacherSessionScreen to show real-time attendance as students
  /// arrive and their proofs are written to the local DB and synced back
  /// by the FirebaseSyncEngine.
  Stream<List<AttendanceProof>> watchProofsForSession(String sessionId) {
    return (select(attendanceProofs)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // DAO: MessageRecords
  // ────────────────────────────────────────────────────────────────────────────

  /// Insert or update a message (idempotent — same UUID = same message).
  Future<void> upsertMessage(MessageRecordsCompanion msg) {
    return into(messageRecords).insertOnConflictUpdate(msg);
  }

  /// All BROADCAST messages ordered newest-first — for the Social feed.
  /// Excludes direct messages (recipientUid != null) — Milestone 7 added
  /// DMs to the same table; without this filter they would leak into the
  /// public group chat view.
  Future<List<MessageRecord>> allMessages({int limit = 100}) {
    return (select(messageRecords)
          ..where((t) => t.recipientUid.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .get();
  }

  /// Unsynced messages for cloud upload.
  Future<List<MessageRecord>> unsyncedMessages() {
    return (select(messageRecords)
          ..where((t) => t.synced.equals(false)))
        .get();
  }

  /// Mark a message as synced.
  Future<void> markMessageSynced(String id) {
    return (update(messageRecords)..where((t) => t.id.equals(id)))
        .write(const MessageRecordsCompanion(synced: Value(true)));
  }

  /// Live-updating BROADCAST message list, newest-first — used by
  /// SocialScreen. Emits on every insert/delete without manual polling.
  /// Excludes direct messages — see [allMessages] for why.
  Stream<List<MessageRecord>> watchAllMessages({int limit = 200}) {
    return (select(messageRecords)
          ..where((t) => t.recipientUid.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .watch();
  }

  /// Live-updating message list for a single 1:1 DM thread (either
  /// direction — sent by me to peer, or sent by peer to me), newest-first.
  /// Used by DirectMessageScreen.
  Stream<List<MessageRecord>> watchDirectMessages(
    String myUid,
    String peerUid, {
    int limit = 200,
  }) {
    return (select(messageRecords)
          ..where((t) =>
              (t.senderUid.equals(myUid) & t.recipientUid.equals(peerUid)) |
              (t.senderUid.equals(peerUid) & t.recipientUid.equals(myUid)))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .watch();
  }

  /// Delete messages older than the retention period (30 days).
  Future<int> purgeOldMessages(DateTime cutoff) {
    return (delete(messageRecords)
          ..where((t) => t.timestamp.isSmallerThanValue(cutoff)))
        .go();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // DAO: SosRecords
  // ────────────────────────────────────────────────────────────────────────────

  /// Insert or update an SOS event.
  Future<void> upsertSosRecord(SosRecordsCompanion sos) {
    return into(sosRecords).insertOnConflictUpdate(sos);
  }

  /// Unsynced SOS events — highest priority for sync engine.
  Future<List<SosRecord>> unsyncedSosRecords() {
    return (select(sosRecords)
          ..where((t) => t.synced.equals(false)))
        .get();
  }

  /// Mark SOS as synced.
  Future<void> markSosSynced(String id) {
    return (update(sosRecords)..where((t) => t.id.equals(id)))
        .write(const SosRecordsCompanion(synced: Value(true)));
  }

  // ────────────────────────────────────────────────────────────────────────────
  // DAO: SeenPackets (deduplication)
  // ────────────────────────────────────────────────────────────────────────────

  /// Returns true if this packet has already been processed by this node.
  Future<bool> hasSeenPacket(String packetId) async {
    final row = await (select(seenPackets)
          ..where((t) => t.packetId.equals(packetId)))
        .getSingleOrNull();
    return row != null;
  }

  /// Record a packet as seen (no-op if already present — safe to call twice).
  Future<void> markPacketSeen(String packetId) {
    return into(seenPackets).insertOnConflictUpdate(
      SeenPacketsCompanion(
        packetId: Value(packetId),
        firstSeen: Value(DateTime.now()),
      ),
    );
  }

  /// Purge seen-packet entries older than [cutoff] (called every 60 minutes).
  Future<int> purgeOldSeenPackets(DateTime cutoff) {
    return (delete(seenPackets)
          ..where((t) => t.firstSeen.isSmallerThanValue(cutoff)))
        .go();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // DAO: Peers
  // ────────────────────────────────────────────────────────────────────────────

  /// Upsert a peer record on every BLE advertisement received from that peer.
  Future<void> upsertPeer(PeersCompanion peer) {
    return into(peers).insertOnConflictUpdate(peer);
  }

  /// All peers seen within the last [maxAge] duration.
  Future<List<Peer>> recentPeers({Duration maxAge = const Duration(minutes: 5)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    return (select(peers)
          ..where((t) => t.lastSeen.isBiggerThanValue(cutoff))
          ..orderBy([(t) => OrderingTerm.desc(t.lastSeen)]))
        .get();
  }

  /// Remove peers not seen within the retention period (7 days).
  Future<int> purgeStalePeers(DateTime cutoff) {
    return (delete(peers)
          ..where((t) => t.lastSeen.isSmallerThanValue(cutoff)))
        .go();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Maintenance: call from a periodic timer in MeshService (Milestone 3)
  // ────────────────────────────────────────────────────────────────────────────

  /// Single call to run all purge operations. Called every 30 minutes by
  /// MeshService's maintenance timer — running more frequently than the purge
  /// cutoffs (60 min for SeenPackets, 30 days for messages, 7 days for peers)
  /// is intentional: the extra calls are no-ops when no rows are old enough
  /// to evict, and the 30-minute cadence ensures the DB stays lean throughout
  /// a full campus day without waiting a full hour between passes.
  Future<void> runMaintenance() async {
    final now = DateTime.now();
    await purgeOldSeenPackets(now.subtract(const Duration(minutes: 60)));
    await purgeOldMessages(now.subtract(const Duration(days: 30)));
    await purgeStalePeers(now.subtract(const Duration(days: 7)));
  }
}
