// ── AttendanceService — VEXT Lane A Smart Attendance ──────────────────────────
//
// Manages the full attendance lifecycle for BOTH teacher and student roles.
// Sits on top of MeshService — does NOT call BleTransportLayer directly.
//
// ── Teacher flow ──────────────────────────────────────────────────────────────
//   1. startSession(courseId) →
//        - Generates a UUID session ID.
//        - Generates HMAC-SHA256 token via CryptoService (90-second window).
//        - Broadcasts MeshPacket.attendance via mesh.sendPacket() (GATT path).
//        - Creates Firestore session document.
//        - Starts a timer to re-broadcast every 5 seconds.
//        - Starts a token-refresh timer to regenerate HMAC every 89 seconds
//          (just before the window expires) and immediately re-broadcast.
//   2. stopSession() →
//        - Cancels broadcast timers.
//        - Marks session closed in Firestore.
//        - Resets active session state.
//
// ── Student flow ──────────────────────────────────────────────────────────────
//   1. Listens to mesh.attendancePackets (full GATT packets, rssi=0).
//   2. When a packet arrives:
//        - Decodes payload: sessionId + hmacToken.
//        - Skips if already submitted proof for this session.
//        - Assembles AttendanceProof (id, sessionId, studentUid, hmacToken,
//          rssi from BLE GATT connection, timestamp, GPS if available).
//        - Saves to Drift DB via db.upsertAttendanceProof().
//        - Calls syncEngine.syncNow() to upload to Firestore immediately.
//        - Emits updated status on attendanceStatusStream.
//   3. Also subscribes to mesh.attendanceAdvertisements (advertisement path,
//      real RSSI). When an advertisement arrives for a session not yet proven,
//      records the RSSI for use in the next GATT proof assembly.
//
// ── RSSI Note ─────────────────────────────────────────────────────────────────
// GATT packets carry rssi=0 (RSSI not available post-connection). The closest
// physical proximity evidence for GATT is that a BLE connection succeeded at all
// (typically requires < 15 m). For the academic demo this is sufficient.
// When an advertisement-path packet also arrives (attendanceAdvertisements stream),
// we upgrade the proof RSSI with the real advertisement RSSI value.
// Full dual-mode RSSI verification will be added in Milestone 7.
//
// ── HMAC Note ────────────────────────────────────────────────────────────────
// The HMAC is keyed to the teacher's private Ed25519 key. Students cannot
// generate or verify it — they pass it unchanged in the AttendanceProof.
// Teacher-side verification happens when reviewing proofs from Firestore:
// the teacher's app calls crypto.verifyHmacToken() for each proof.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

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

// ── AttendanceSession ──────────────────────────────────────────────────────────

/// In-memory representation of an active or recently closed session.
/// Stored in Firestore via [AttendanceService.startSession].
class AttendanceSession {
  AttendanceSession({
    required this.id,
    required this.courseId,
    required this.teacherUid,
    required this.startTime,
    required this.currentHmacToken,
    this.isActive = true,
  });

  final String id;           // UUID v4 — session identifier
  final String courseId;     // e.g. "CS101"
  final String teacherUid;   // Firebase UID of the creating teacher
  final DateTime startTime;
  String currentHmacToken;   // Refreshed every ~89 s
  bool isActive;

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'courseId': courseId,
        'teacherUid': teacherUid,
        'startTime': Timestamp.fromDate(startTime),
        'isActive': isActive,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ── AttendanceStatus ───────────────────────────────────────────────────────────

/// Status emitted by [AttendanceService.attendanceStatusStream] on the student side.
enum AttendanceStatusType { idle, detecting, markedPresent, error }

class AttendanceStatus {
  const AttendanceStatus({
    required this.type,
    this.sessionId,
    this.courseId,
    this.proofId,
    this.rssi,
    this.error,
  });

  const AttendanceStatus.idle()
      : type = AttendanceStatusType.idle,
        sessionId = null,
        courseId = null,
        proofId = null,
        rssi = null,
        error = null;

  final AttendanceStatusType type;
  final String? sessionId;
  final String? courseId;
  final String? proofId;
  final int? rssi;       // RSSI at time of marking (0 = GATT, -ve = advertisement)
  final String? error;
}

// ── AttendanceService ──────────────────────────────────────────────────────────

class AttendanceService {
  AttendanceService({
    required MeshService mesh,
    required AppDatabase db,
    required CryptoService crypto,
    required FirebaseSyncEngine syncEngine,
    required String currentUserUid,
    FirebaseFirestore? firestore,
  })  : _mesh = mesh,
        _db = db,
        _crypto = crypto,
        _syncEngine = syncEngine,
        _currentUserUid = currentUserUid,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final MeshService _mesh;
  final AppDatabase _db;
  final CryptoService _crypto;
  final FirebaseSyncEngine _syncEngine;
  final String _currentUserUid;
  final FirebaseFirestore _firestore;

  // ── Active session (teacher side) ──────────────────────────────────────────
  AttendanceSession? _activeSession;
  AttendanceSession? get activeSession => _activeSession;

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _broadcastTimer;
  Timer? _tokenRefreshTimer;

  // ── Student-side RSSI cache ────────────────────────────────────────────────
  // Tracks the best (least-negative = physically closest) RSSI seen from any
  // attendance advertisement in the last 30 seconds.
  //
  // We do NOT key by sessionId or packet UUID here because:
  //   - Advertisement-path packets carry NO sessionId (only type+ttl+uuid).
  //   - The sessionId only arrives with the full GATT packet.
  //   - In a classroom there is one active teacher session at a time.
  //
  // The bug in the previous implementation: the check read from
  //   _advertisementRssiCache[adv.packet.id]   ← always null (nothing stored there)
  // but the store wrote to
  //   _advertisementRssiCache['__latest__']    ← the check was always skipped
  // so every advertisement overwrote the cache unconditionally, discarding
  // any better reading captured earlier.
  //
  // Fix: use two plain fields with an explicit "best RSSI" comparison and a
  // 30-second staleness window so stale values from a previous session are
  // never applied to the next proof assembly.
  int? _bestAdvertisementRssi;
  DateTime? _bestAdvertisementRssiTime;

  // ── Student-side already-submitted sessions ────────────────────────────────
  final Set<String> _submittedSessionIds = {};

  // ── Teacher-side ACK deduplication (Fix 4A) ────────────────────────────────
  // Tracks "sessionId:studentUid" pairs already written to local Drift DB via
  // BLE ACK. Without this, re-broadcast ACKs (e.g. student sends 3 ACKs before
  // teacher receives one) create duplicate rows because Drift's primary key is
  // the proof UUID which we generate fresh each time — NOT studentUid.
  // This is faster than a DB lookup and has no race condition: it's only
  // written from the single mesh event handler on the Dart event loop.
  final Set<String> _localAckedStudents = {};

  // ── Stream controllers ─────────────────────────────────────────────────────
  final _statusController =
      StreamController<AttendanceStatus>.broadcast();

  /// Teacher: live proof list for a session — call watchProofs(sessionId).
  /// Student: status updates — subscribe to attendanceStatusStream.
  Stream<AttendanceStatus> get attendanceStatusStream => _statusController.stream;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<MeshPacket>? _packetSub;
  StreamSubscription<AttendanceAdvertisement>? _advSub;
  /// Teacher-side: listens for ACK packets sent by students after marking
  /// attendance. Writes a local Drift proof so the teacher's dashboard works
  /// fully offline without Firestore (Fix 4A).
  StreamSubscription<MeshPacket>? _ackSub;

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Wire mesh streams. Call once after construction.
  void initialize() {
    // Student-side: full GATT packets (have payload, rssi=0)
    _packetSub = _mesh.attendancePackets.listen(_onAttendancePacket);

    // Student-side: advertisement-only packets (no payload, real RSSI)
    // Cache the best RSSI per session for use when GATT proof arrives.
    _advSub = _mesh.attendanceAdvertisements.listen(_onAttendanceAdvertisement);

    // Teacher-side: ACK packets from students (Fix 4A).
    // Students send an attendanceAck after successfully saving their proof.
    // The teacher writes these to local Drift DB so the dashboard works offline.
    //
    // We wrap in a lambda rather than passing _onAttendanceAckPacket directly
    // because the stream listener signature is void Function(T). If the handler
    // were async the Future would be silently dropped. The wrapper makes the
    // fire-and-forget explicit and errors surface via catchError instead of
    // disappearing into an unhandled Future.
    _ackSub = _mesh.ackPackets.listen((packet) {
      _onAttendanceAckPacket(packet);
    });

    _statusController.add(const AttendanceStatus.idle());
  }

  // ── Teacher API ────────────────────────────────────────────────────────────

  /// Start an attendance session for [courseId].
  ///
  /// Generates a session UUID, creates an HMAC token, broadcasts the attendance
  /// packet immediately and then every [AppConstants.attendanceAdvertiseIntervalMs]
  /// milliseconds. Also refreshes the HMAC token just before each 90-second
  /// window boundary to prevent clock-drift rejections at window edge.
  ///
  /// Returns the [AttendanceSession] on success.
  Future<AttendanceSession> startSession(String courseId) async {
    // Stop any existing session first.
    if (_activeSession != null && _activeSession!.isActive) {
      await stopSession();
    }

    final sessionId = const Uuid().v4();
    final hmacToken = await _crypto.generateHmacToken(sessionId, courseId);

    _activeSession = AttendanceSession(
      id: sessionId,
      courseId: courseId,
      teacherUid: _currentUserUid,
      startTime: DateTime.now(),
      currentHmacToken: hmacToken,
    );

    // Write session doc to Firestore's local cache (instant — works offline).
    // Firestore offline persistence queues the write and delivers it to the
    // server automatically when connectivity is available.
    //
    // We do NOT call waitForPendingWrites() here. That call blocks for up to
    // 10 seconds without internet, freezing the UI before BLE even starts.
    // The session is valid the moment it is written to the local cache — BLE
    // broadcasting starts immediately below, regardless of internet state.
    //
    // Consequence: watchFirestoreProofs() will show a permission-denied error
    // until the session doc reaches the Firestore server (requires internet).
    // The local BLE attendance flow (Fix 4A) is the offline fallback.
    await _writeSessionToFirestore(_activeSession!);

    // Broadcast immediately, then on a timer.
    await _broadcastAttendancePacket();

    _broadcastTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.attendanceAdvertiseIntervalMs),
      (_) => _broadcastAttendancePacket(),
    );

    // Refresh HMAC every 89 seconds (1 second before the 90-second window rolls).
    // This ensures the token is always fresh and students never receive an
    // immediately-expired token.
    _tokenRefreshTimer = Timer.periodic(
      const Duration(seconds: 89),
      (_) async {
        if (_activeSession == null || !_activeSession!.isActive) return;
        _activeSession!.currentHmacToken = await _crypto.generateHmacToken(
          _activeSession!.id,
          _activeSession!.courseId,
        );
      },
    );

    return _activeSession!;
  }

  /// Stop the active session.
  Future<void> stopSession() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;

    if (_activeSession != null) {
      _activeSession!.isActive = false;
      // Fire-and-forget: marking a session inactive has no security implications.
      // No waitForPendingWrites needed — no Firestore rule reads this value.
      _writeSessionToFirestore(_activeSession!).ignore();
    }

    _activeSession = null;
    // Clear teacher-side ACK dedup cache when session ends.
    _localAckedStudents.clear();
  }

  /// Live stream of attendance proofs for [sessionId] from the LOCAL Drift DB.
  ///
  /// After Fix 4A this stream is non-empty on the teacher's device: when a
  /// student marks attendance and sends an ACK packet via BLE, [_onAttendanceAckPacket]
  /// writes it here. This is the offline dashboard source when Firestore is
  /// unavailable. For the full cloud-synced view (students not in BLE range),
  /// use [watchFirestoreProofs] — TeacherSessionScreen shows both with fallback.
  Stream<List<AttendanceProof>> watchProofs(String sessionId) {
    return _db.watchProofsForSession(sessionId);
  }

  /// Live stream of attendance proofs for [sessionId] from FIRESTORE.
  ///
  /// This is the correct source for the teacher's live attendance dashboard.
  /// Proofs are written here by the FirebaseSyncEngine running on each student's
  /// device. The collection path is:
  ///   attendance/{sessionId}/proofs/{studentUid}
  ///
  /// Each document in the snapshot is emitted as a [Map<String, dynamic>]
  /// matching the fields written by [FirebaseSyncEngine._syncAttendanceProofs]:
  ///   id, sessionId, studentUid, hmacToken, rssi, timestamp, gpsLat, gpsLng
  ///
  /// Results are ordered by timestamp descending (newest first).
  Stream<List<Map<String, dynamic>>> watchFirestoreProofs(String sessionId) {
    return _firestore
        .collection(AppConstants.fsAttendance)
        .doc(sessionId)
        .collection(AppConstants.fsProofs)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()).toList());
  }

  // ── Student API ────────────────────────────────────────────────────────────

  /// Verify a received HMAC token against the teacher's expected token.
  ///
  /// NOTE: This uses the LOCAL device's HMAC key — it only works correctly
  /// if the student IS the teacher (self-test scenario). In production,
  /// students pass the token unchanged and the teacher verifies on their device.
  /// Full cross-device verification is in Milestone 7 via Firestore key exchange.
  Future<bool> verifyToken(
    String sessionId,
    String courseId,
    String tokenHex,
  ) async {
    return _crypto.verifyHmacToken(sessionId, courseId, tokenHex);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopSession();
    await _packetSub?.cancel();
    await _advSub?.cancel();
    await _ackSub?.cancel();
    _statusController.close();
    _bestAdvertisementRssi = null;
    _bestAdvertisementRssiTime = null;
    _submittedSessionIds.clear();
    _localAckedStudents.clear();
  }

  // ── Private — broadcast ────────────────────────────────────────────────────

  Future<void> _broadcastAttendancePacket() async {
    final session = _activeSession;
    if (session == null || !session.isActive) return;

    final packet = MeshPacket.attendance(
      id: const Uuid().v4(),
      senderUid: _currentUserUid,
      sessionId: session.id,
      hmacToken: session.currentHmacToken,
    );

    await _mesh.sendPacket(packet);

    // Also advertise the 18-byte header so students scanning can capture RSSI.
    // transport.advertisePacket() is called via the BleTransportLayer reference
    // inside MeshService's transport field — but MeshService doesn't expose
    // transport directly. Instead we rely on mesh.sendPacket() which triggers
    // a GATT write to all known peers, and the continuous heartbeat advertisement
    // already running in BleTransportLayer keeps us discoverable.
    // RSSI-targeted advertisement will be added in Milestone 7.
  }

  // ── Private — incoming packet handler (student side) ──────────────────────

  void _onAttendancePacket(MeshPacket packet) {
    // Ignore our own packets (teacher broadcasting) to avoid self-marking.
    if (packet.senderUid == _currentUserUid) return;

    final decoded = packet.decodeAttendancePayload();
    if (decoded == null) return;

    final sessionId = decoded.sessionId;
    final hmacToken = decoded.hmacToken;

    // Don't submit a second proof for the same session.
    if (_submittedSessionIds.contains(sessionId)) return;

    _statusController.add(AttendanceStatus(
      type: AttendanceStatusType.detecting,
      sessionId: sessionId,
    ));

    _assembleAndSubmitProof(
      sessionId: sessionId,
      hmacToken: hmacToken,
      gattRssi: 0, // GATT path — real RSSI not available post-connection
    );
  }

  void _onAttendanceAdvertisement(AttendanceAdvertisement adv) {
    // Keep the best (least-negative = physically closest) RSSI seen from
    // any attendance advertisement in the last 30 seconds.
    //
    // "Best" means the reading where the student was physically closest to
    // the teacher at the time of scanning — higher RSSI (less negative) is
    // better. We update only if the new reading is better than the stored one.
    //
    // The 30-second window ensures stale readings from a previous session
    // are never accidentally applied to the current proof assembly.
    final now = DateTime.now();
    final isStale = _bestAdvertisementRssiTime == null ||
        now.difference(_bestAdvertisementRssiTime!) >
            const Duration(seconds: 30);

    final isBetter = _bestAdvertisementRssi == null ||
        adv.rssi > _bestAdvertisementRssi!;

    if (isStale || isBetter) {
      _bestAdvertisementRssi = adv.rssi;
      _bestAdvertisementRssiTime = now;
    }
  }

  Future<void> _assembleAndSubmitProof({
    required String sessionId,
    required String hmacToken,
    required int gattRssi,
  }) async {
    // Upgrade RSSI with the best advertisement-path reading if it was captured
    // within the last 30 seconds. Clear the cache after consuming it so a
    // single advertisement reading is never applied to two different proofs.
    int? advertisementRssi;
    final rssiCheckTime = DateTime.now();
    if (_bestAdvertisementRssi != null &&
        _bestAdvertisementRssiTime != null &&
        rssiCheckTime.difference(_bestAdvertisementRssiTime!) <=
            const Duration(seconds: 30)) {
      advertisementRssi = _bestAdvertisementRssi;
    }
    // Clear cache regardless — prevents stale data from leaking into the next proof.
    _bestAdvertisementRssi = null;
    _bestAdvertisementRssiTime = null;

    final effectiveRssi = advertisementRssi ?? gattRssi;

    // Check minimum RSSI gate. GATT rssi=0 bypasses the gate (we trust
    // GATT connection proximity — a connection at all requires < 15 m).
    // Advertisement RSSI uses rssiThresholdAttendance (-85 dBm) which is
    // intentionally softer than the mesh relay threshold (-75 dBm) to avoid
    // false-rejections caused by body shielding or device orientation.
    if (effectiveRssi != 0 &&
        effectiveRssi < AppConstants.rssiThresholdAttendance) {
      // Too far away — do not mark present.
      _statusController.add(AttendanceStatus(
        type: AttendanceStatusType.error,
        sessionId: sessionId,
        error: 'Signal too weak (${effectiveRssi} dBm). Move closer.',
      ));
      return;
    }

    final proofId = const Uuid().v4();
    final now = DateTime.now();

    final proof = AttendanceProofsCompanion(
      id: Value(proofId),
      sessionId: Value(sessionId),
      studentUid: Value(_currentUserUid),
      hmacToken: Value(hmacToken),
      rssi: Value(effectiveRssi),
      timestamp: Value(now),
      gpsLat: const Value<double?>(null),   // GPS proximity added in Milestone 7
      gpsLng: const Value<double?>(null),
      synced: const Value(false),
    );

    try {
      await _db.upsertAttendanceProof(proof);
      _submittedSessionIds.add(sessionId);

      // Send an ACK packet back to the mesh (Fix 4A).
      // The teacher's AttendanceService listens to ackPackets and writes the
      // ACK to its local Drift DB, enabling an offline attendance dashboard.
      // TTL=3: short hop — only needs to reach the teacher node.
      // Fire-and-forget: ACK delivery is best-effort; the student's proof is
      // already saved locally and will sync to Firestore when online.
      _mesh.sendPacket(
        MeshPacket.attendanceAck(
          id: const Uuid().v4(),
          senderUid: _currentUserUid,
          sessionId: sessionId,
          hmacToken: hmacToken,
          rssi: effectiveRssi,
        ),
      ).ignore();

      // Trigger immediate sync so proof appears in teacher's Firebase dashboard.
      _syncEngine.syncNow().ignore();

      _statusController.add(AttendanceStatus(
        type: AttendanceStatusType.markedPresent,
        sessionId: sessionId,
        proofId: proofId,
        rssi: effectiveRssi,
      ));
    } catch (e) {
      _statusController.add(AttendanceStatus(
        type: AttendanceStatusType.error,
        sessionId: sessionId,
        error: 'Failed to save proof: $e',
      ));
    }
  }

  // ── Private — Teacher ACK handler (Fix 4A) ─────────────────────────────────

  /// Called when an ACK packet arrives on the mesh.
  ///
  /// If this device is the active teacher and the ACK is for our current session,
  /// write the student's proof to local Drift DB. This gives the teacher a
  /// live attendance list that works fully offline — no Firestore needed.
  ///
  /// Deduplication: handled by [_localAckedStudents], an in-memory Set keyed
  /// by "sessionId:studentUid". Drift's primary key is the proof UUID (generated
  /// fresh per ACK), so DB-level dedup alone would not prevent duplicates.
  void _onAttendanceAckPacket(MeshPacket packet) {
    // Only process ACKs if we are the active teacher.
    final session = _activeSession;
    if (session == null || !session.isActive) return;

    // Ignore our own echoed packets.
    if (packet.senderUid == _currentUserUid) return;

    final decoded = packet.decodeAttendanceAckPayload();
    if (decoded == null) return;

    // Only process ACKs for our current session.
    if (decoded.sessionId != session.id) return;

    // Dedup: one local proof per student per session.
    // The Drift primary key is the proof UUID (not studentUid), so if we
    // generate a fresh UUID per ACK, re-broadcasts create duplicate rows and
    // the teacher's list shows the same student multiple times.
    // _localAckedStudents is the authoritative in-memory dedup guard —
    // cheaper than a DB query and race-free (single event-loop thread).
    final ackKey = '${session.id}:${packet.senderUid}';
    if (_localAckedStudents.contains(ackKey)) return;
    _localAckedStudents.add(ackKey);

    debugPrint('[Attendance] Teacher received ACK from ${packet.senderUid} '
        '— writing local proof (offline fallback)');

    // Build a local proof from the ACK data.
    // proofId is a fresh UUID — the student's proofId is not transmitted.
    // Dedup is handled by _localAckedStudents above, not by the DB primary key.
    final localProof = AttendanceProofsCompanion(
      id: Value(const Uuid().v4()),
      sessionId: Value(session.id),
      studentUid: Value(packet.senderUid),
      hmacToken: Value(decoded.hmacToken),
      rssi: Value(decoded.rssi),
      timestamp: Value(packet.timestamp),
      gpsLat: const Value<double?>(null),
      gpsLng: const Value<double?>(null),
      // Mark synced=true — the STUDENT's device handles the Firestore upload.
      // We don't want the teacher's sync engine to re-upload this proof.
      synced: const Value(true),
    );

    _db.upsertAttendanceProof(localProof).catchError((e) {
      debugPrint('[Attendance] Failed to write ACK proof locally: $e');
    });
  }

  // ── Private — Firestore ────────────────────────────────────────────────────

  /// Write (or update) the session document in Firestore's local cache.
  ///
  /// The write is committed to the local offline cache immediately (no network
  /// required). Firestore's persistence layer delivers it to the server when
  /// connectivity is available.
  ///
  /// [startSession] awaits this call so the session object exists in the cache
  /// before BLE broadcasting begins. [stopSession] does NOT await it — marking
  /// a session inactive is not security-critical.
  Future<void> _writeSessionToFirestore(AttendanceSession session) {
    return _firestore
        .collection(AppConstants.fsSessions)
        .doc(session.id)
        .set(session.toFirestore(), SetOptions(merge: true));
  }
}
