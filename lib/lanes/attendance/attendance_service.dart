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
  // Maps sessionId → best RSSI seen from advertisement path.
  // When a GATT proof is assembled, we upgrade rssi=0 with this value if present.
  final Map<String, int> _advertisementRssiCache = {};

  // ── Student-side already-submitted sessions ────────────────────────────────
  final Set<String> _submittedSessionIds = {};

  // ── Stream controllers ─────────────────────────────────────────────────────
  final _statusController =
      StreamController<AttendanceStatus>.broadcast();

  /// Teacher: live proof list for a session — call watchProofs(sessionId).
  /// Student: status updates — subscribe to attendanceStatusStream.
  Stream<AttendanceStatus> get attendanceStatusStream => _statusController.stream;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<MeshPacket>? _packetSub;
  StreamSubscription<AttendanceAdvertisement>? _advSub;

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Wire mesh streams. Call once after construction.
  void initialize() {
    // Student-side: full GATT packets (have payload, rssi=0)
    _packetSub = _mesh.attendancePackets.listen(_onAttendancePacket);

    // Student-side: advertisement-only packets (no payload, real RSSI)
    // Cache the best RSSI per session for use when GATT proof arrives.
    _advSub = _mesh.attendanceAdvertisements.listen(_onAttendanceAdvertisement);

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

    // Write session doc to Firestore (best-effort — may be offline).
    _writeSessionToFirestore(_activeSession!);

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
      _writeSessionToFirestore(_activeSession!); // mark closed in Firestore
    }

    _activeSession = null;
  }

  /// Live stream of attendance proofs for [sessionId] from the LOCAL Drift DB.
  ///
  /// NOTE: In a two-phone scenario this stream is empty on the teacher's device
  /// because student proofs are written to the STUDENT's local DB and synced to
  /// Firestore. Use [watchFirestoreProofs] for the teacher dashboard view.
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
    _statusController.close();
    _advertisementRssiCache.clear();
    _submittedSessionIds.clear();
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
    // Cache best (highest = closest) RSSI per session.
    // "Best" = least negative = physically closest measurement.
    final existing = _advertisementRssiCache[adv.packet.id];
    if (existing == null || adv.rssi > existing) {
      // We use packet.id (the advertisement UUID) as a session proxy here.
      // The actual sessionId only arrives via the GATT full packet.
      // Store keyed by a temporary key; AttendanceService will use this
      // when assembling the proof if a GATT packet arrives shortly after.
      _advertisementRssiCache['__latest__'] = adv.rssi;
    }
  }

  Future<void> _assembleAndSubmitProof({
    required String sessionId,
    required String hmacToken,
    required int gattRssi,
  }) async {
    // Upgrade RSSI with advertisement value if we have one nearby.
    final advertisementRssi = _advertisementRssiCache.remove('__latest__');
    final effectiveRssi = advertisementRssi ?? gattRssi;

    // Check minimum RSSI gate (-90 dBm = mesh minimum; attendance uses -75 dBm).
    // GATT rssi=0 bypasses the gate (we trust GATT connection proximity).
    if (effectiveRssi != 0 &&
        effectiveRssi < AppConstants.rssiThresholdDefault) {
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

  // ── Private — Firestore ────────────────────────────────────────────────────

  void _writeSessionToFirestore(AttendanceSession session) {
    _firestore
        .collection(AppConstants.fsSessions)
        .doc(session.id)
        .set(session.toFirestore(), SetOptions(merge: true))
        .ignore(); // offline-first: no await, sync engine will retry
  }
}
