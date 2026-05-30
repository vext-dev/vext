// ── Drift Table Definitions ────────────────────────────────────────────────────
//
// All five database tables for VEXT VigilantMesh.
//
// HOW DRIFT WORKS:
//  1. These classes declare the *schema* — column names and types.
//  2. Run:  dart run build_runner build --delete-conflicting-outputs
//     This generates drift_service.g.dart with the actual SQL + data classes.
//  3. The generated data classes (AttendanceProof, MessageRecord, etc.) and
//     companion insert classes are used throughout the app.
//
// Never edit drift_service.g.dart by hand.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

// ── 1. AttendanceProofs ───────────────────────────────────────────────────────
//
// Written when a student's BLE advertisement is detected by a teacher node
// within RSSI threshold. One row per student per session, pending cloud sync.
//
class AttendanceProofs extends Table {
  /// UUID v4 — packet ID from the mesh packet that carried this proof.
  TextColumn get id => text().withLength(min: 36, max: 36)();

  /// Session ID broadcast by the teacher node.
  TextColumn get sessionId => text().withLength(min: 36, max: 36)();

  /// Firebase UID of the student whose presence is being recorded.
  TextColumn get studentUid => text()();

  /// HMAC-SHA256 token proving temporal presence (90 s rolling window).
  TextColumn get hmacToken => text()();

  /// Raw RSSI value at time of capture (negative integer, e.g. -65).
  IntColumn get rssi => integer()();

  /// Unix timestamp of BLE packet capture.
  DateTimeColumn get timestamp => dateTime()();

  /// GPS latitude at time of capture — null when location unavailable.
  RealColumn get gpsLat => real().nullable()();

  /// GPS longitude at time of capture — null when location unavailable.
  RealColumn get gpsLng => real().nullable()();

  /// False until this row is successfully written to Firestore.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── 2. MessageRecords ─────────────────────────────────────────────────────────
//
// Social mesh messages (Lane B). Content is encrypted with the recipient's
// public key in Milestone 3. For now the field stores plaintext in dev builds.
//
class MessageRecords extends Table {
  /// UUID v4 — globally unique across the mesh (used for dedup).
  TextColumn get id => text().withLength(min: 36, max: 36)();

  /// Firebase UID of the originating node.
  TextColumn get senderUid => text()();

  /// Encrypted message content. In Milestone 2: UTF-8 plaintext.
  /// In Milestone 3: base64-encoded XSalsa20-Poly1305 ciphertext.
  TextColumn get contentEncrypted => text()();

  /// Remaining hops. Decremented by each relay node. Drop at 0.
  IntColumn get ttl => integer()();

  /// Original send time from the originating node.
  DateTimeColumn get timestamp => dateTime()();

  /// Routing lane identifier: 'social' | 'broadcast'.
  TextColumn get lane =>
      text().withDefault(const Constant('social'))();

  /// False until this row is synced to Firestore cloud storage.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  /// Whether the local user has read this message.
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── 3. SosRecords ─────────────────────────────────────────────────────────────
//
// SOS emergency events (Lane C). TTL=255, re-broadcast every 2 s, bypasses
// all rate limiting. Synced to Firestore immediately; triggers Cloud Function
// that sends FCM push to all security nodes.
//
class SosRecords extends Table {
  /// UUID v4 — globally unique SOS event ID.
  TextColumn get id => text().withLength(min: 36, max: 36)();

  /// Firebase UID of the person who triggered SOS.
  TextColumn get senderUid => text()();

  /// GPS latitude at time of SOS trigger.
  RealColumn get latitude => real()();

  /// GPS longitude at time of SOS trigger.
  RealColumn get longitude => real()();

  /// Remaining hops (starts at 255, decremented per relay).
  IntColumn get ttl => integer()();

  /// Unix timestamp when SOS was first triggered.
  DateTimeColumn get timestamp => dateTime()();

  /// False until this event is acknowledged by Firestore.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── 4. SeenPackets ────────────────────────────────────────────────────────────
//
// Deduplication table. Before relaying any packet, the mesh engine checks
// whether the packet_id already exists here. If it does, drop it silently.
// Rows are purged after 60 minutes (AppConstants.seenTableTtl).
//
class SeenPackets extends Table {
  /// UUID of the mesh packet already processed.
  TextColumn get packetId => text().withLength(min: 36, max: 36)();

  /// When this node first processed the packet — used for TTL purge.
  DateTimeColumn get firstSeen => dateTime()();

  @override
  Set<Column> get primaryKey => {packetId};
}

// ── 5. Peers ──────────────────────────────────────────────────────────────────
//
// Known BLE peers encountered during scanning. Updated every time a peer's
// advertisement is received. Rows older than 7 days are purged.
//
class Peers extends Table {
  /// Firebase UID of the remote peer node.
  TextColumn get peerUid => text()();

  /// When this peer was last seen advertising.
  DateTimeColumn get lastSeen => dateTime()();

  /// Last measured RSSI from this peer (signal strength indicator).
  IntColumn get rssi => integer()();

  /// SHA256 fingerprint of peer's Curve25519 public key — set in Milestone 3.
  TextColumn get publicKeyFingerprint =>
      text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {peerUid};
}
