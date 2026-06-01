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
  int get schemaVersion => 1;

  // ── Migration ────────────────────────────────────────────────────────────────
  // v1: initial schema — no migrations needed yet.
  // When adding columns in future milestones, bump schemaVersion and add a
  // MigrationStrategy here. Never rename/drop columns in production without
  // a migration.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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

  /// All messages ordered newest-first — for the Social feed.
  Future<List<MessageRecord>> allMessages({int limit = 100}) {
    return (select(messageRecords)
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

  /// Live-updating message list, newest-first — used by SocialScreen.
  /// Emits on every insert/delete without manual polling.
  Stream<List<MessageRecord>> watchAllMessages({int limit = 200}) {
    return (select(messageRecords)
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

  /// Single call to run all purge operations. Intended to be called every hour.
  Future<void> runMaintenance() async {
    final now = DateTime.now();
    await purgeOldSeenPackets(now.subtract(const Duration(minutes: 60)));
    await purgeOldMessages(now.subtract(const Duration(days: 30)));
    await purgeStalePeers(now.subtract(const Duration(days: 7)));
  }
}
