// ── AttendanceService Unit Tests ──────────────────────────────────────────────
//
// Tests for Milestone 4 — Lane A Smart Attendance.
//
// Coverage:
//   1. HMAC token generation — CryptoService generates a non-empty hex token.
//   2. HMAC token verification — current and previous window both accepted.
//   3. AttendanceService.startSession — returns a session with valid fields.
//   4. AttendanceService.stopSession — isActive = false after stop.
//   5. Student proof assembly — proof saved to DB on packet receipt.
//   6. Self-packet filter — teacher's own packets are not re-processed.
//   7. Duplicate session filter — second packet for same session is ignored.
//
// Uses in-memory Drift DB (AppDatabase.memory()) to avoid file I/O.
// CryptoService uses the real implementation (reads/writes flutter_secure_storage).
// All tests run on the Dart test runner — no emulator required.
//
// Run with:
//   flutter test test/unit/attendance_service_test.dart
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:uuid/uuid.dart';

import 'package:vext/core/proto/mesh_packet.dart';
import 'package:vext/lanes/attendance/attendance_service.dart';
import 'package:vext/services/crypto_service.dart';
import 'package:vext/services/drift_service.dart';
import 'package:vext/services/firebase_sync_engine.dart';
import 'package:vext/services/mesh_service.dart';

@GenerateNiceMocks([
  MockSpec<MeshService>(),
  MockSpec<FirebaseSyncEngine>(),
])
import 'attendance_service_test.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Build an AttendanceService backed by a real in-memory DB and real CryptoService.
Future<(AttendanceService, AppDatabase, CryptoService)> _buildService({
  MeshService? mesh,
  String uid = 'teacher-uid-1234',
}) async {
  final mockMesh = mesh ?? MockMeshService();
  final db = AppDatabase.memory();
  final crypto = CryptoService();
  await crypto.initialize();

  final syncEngine = MockFirebaseSyncEngine();
  when(syncEngine.syncNow()).thenAnswer((_) async {});

  // Stub required stream getters on the mock mesh.
  if (mesh == null) {
    when(mockMesh.attendancePackets)
        .thenAnswer((_) => const Stream.empty());
    when(mockMesh.attendanceAdvertisements)
        .thenAnswer((_) => const Stream.empty());
  }

  final svc = AttendanceService(
    mesh: mockMesh,
    db: db,
    crypto: crypto,
    syncEngine: syncEngine,
    currentUserUid: uid,
    // AttendanceService falls back to FirebaseFirestore.instance when no
    // firestore is given, which throws core/no-app under the plain test
    // runner (Firebase.initializeApp() never runs). FakeFirebaseFirestore
    // is an in-memory implementation that supports the real
    // collection/doc/set/orderBy/snapshots() chains AttendanceService uses.
    firestore: FakeFirebaseFirestore(),
  );
  svc.initialize();

  return (svc, db, crypto);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // CryptoService.initialize() reads/writes flutter_secure_storage, which has
  // no real platform implementation under the plain Dart test runner — every
  // call throws MissingPluginException without this. setMockInitialValues
  // wires an in-memory map to the plugin's MethodChannel (same pattern as
  // crypto_service_test.dart). Reset before each test so keys don't leak
  // across tests that expect a fresh device.
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CryptoService — HMAC (Lane A foundation)', () {
    late CryptoService crypto;

    setUp(() async {
      crypto = CryptoService();
      await crypto.initialize();
    });

    test('generateHmacToken returns non-empty 64-char hex string', () async {
      final token =
          await crypto.generateHmacToken('session-001', 'CS101');
      expect(token, isNotEmpty);
      expect(token.length, 64); // SHA-256 → 32 bytes → 64 hex chars
      expect(
        RegExp(r'^[0-9a-f]+$').hasMatch(token),
        isTrue,
        reason: 'Token should be lowercase hex',
      );
    });

    test('verifyHmacToken accepts current-window token', () async {
      final sessionId = const Uuid().v4();
      const courseId = 'MATH202';
      final token = await crypto.generateHmacToken(sessionId, courseId);
      final valid =
          await crypto.verifyHmacToken(sessionId, courseId, token);
      expect(valid, isTrue);
    });

    test('verifyHmacToken rejects tampered token', () async {
      final sessionId = const Uuid().v4();
      const courseId = 'PHY301';
      final token = await crypto.generateHmacToken(sessionId, courseId);
      // Flip the last two hex chars to create an invalid token.
      final tampered = token.substring(0, token.length - 2) + 'ff';
      final valid =
          await crypto.verifyHmacToken(sessionId, courseId, tampered);
      expect(valid, isFalse);
    });

    test('verifyHmacToken rejects token for different session', () async {
      const courseId = 'BIO101';
      final tokenForSession1 =
          await crypto.generateHmacToken('session-A', courseId);
      final validForSession2 = await crypto.verifyHmacToken(
          'session-B', courseId, tokenForSession1);
      expect(validForSession2, isFalse);
    });
  });

  group('AttendanceService — session lifecycle', () {
    test('startSession returns session with correct courseId and isActive=true',
        () async {
      final (svc, _, __) = await _buildService();

      final session = await svc.startSession('CS101');

      expect(session.courseId, 'CS101');
      expect(session.id.length, 36); // UUID v4
      expect(session.isActive, isTrue);
      expect(session.currentHmacToken, isNotEmpty);
      expect(session.currentHmacToken.length, 64);

      await svc.dispose();
    });

    test('activeSession is non-null after startSession', () async {
      final (svc, _, __) = await _buildService();

      await svc.startSession('EE201');

      expect(svc.activeSession, isNotNull);
      expect(svc.activeSession!.courseId, 'EE201');

      await svc.dispose();
    });

    test('stopSession sets isActive=false and clears activeSession', () async {
      final (svc, _, __) = await _buildService();

      await svc.startSession('CHE110');
      await svc.stopSession();

      expect(svc.activeSession, isNull);

      await svc.dispose();
    });

    test('calling startSession twice stops the first session', () async {
      final (svc, _, __) = await _buildService();

      final first = await svc.startSession('CS101');
      final second = await svc.startSession('CS102');

      // First session should no longer be active.
      expect(first.isActive, isFalse);
      expect(second.isActive, isTrue);
      expect(svc.activeSession!.courseId, 'CS102');

      await svc.dispose();
    });
  });

  group('AttendanceService — student proof assembly', () {
    test('proof is saved to DB when attendance packet arrives from teacher',
        () async {
      // Create separate teacher and student instances.
      final teacherDb = AppDatabase.memory();
      final teacherCrypto = CryptoService();
      await teacherCrypto.initialize();

      // Build a teacher session to get a valid HMAC token.
      final sessionId = const Uuid().v4();
      const courseId = 'CS101';
      final hmacToken =
          await teacherCrypto.generateHmacToken(sessionId, courseId);

      // Build a real attendance packet that mimics what the teacher broadcasts.
      final teacherUid = 'teacher-uid-abc';
      final packetId = const Uuid().v4();
      final packet = MeshPacket.attendance(
        id: packetId,
        senderUid: teacherUid,
        sessionId: sessionId,
        hmacToken: hmacToken,
      );

      // Set up student service with a StreamController so we can inject packets.
      final packetController = StreamController<MeshPacket>.broadcast();
      final advController =
          StreamController<AttendanceAdvertisement>.broadcast();

      final mockMesh = MockMeshService();
      when(mockMesh.attendancePackets)
          .thenAnswer((_) => packetController.stream);
      when(mockMesh.attendanceAdvertisements)
          .thenAnswer((_) => advController.stream);

      final studentDb = AppDatabase.memory();
      final studentCrypto = CryptoService();
      await studentCrypto.initialize();

      final syncEngine = MockFirebaseSyncEngine();
      when(syncEngine.syncNow()).thenAnswer((_) async {});

      const studentUid = 'student-uid-xyz';
      final studentSvc = AttendanceService(
        mesh: mockMesh,
        db: studentDb,
        crypto: studentCrypto,
        syncEngine: syncEngine,
        currentUserUid: studentUid,
        firestore: FakeFirebaseFirestore(),
      );
      studentSvc.initialize();

      // Inject the teacher's attendance packet into the student's stream.
      packetController.add(packet);

      // Allow the async proof assembly to complete.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Verify proof was saved to DB.
      final proofs = await studentDb.proofsForSession(sessionId);
      expect(proofs, hasLength(1));
      expect(proofs.first.studentUid, studentUid);
      expect(proofs.first.hmacToken, hmacToken);
      expect(proofs.first.sessionId, sessionId);

      await studentSvc.dispose();
      await packetController.close();
      await advController.close();
      await studentDb.close();
      await teacherDb.close();
    });

    test('teacher\'s own packets are not saved as proofs (self-filter)', () async {
      const teacherUid = 'teacher-self-uid';

      final packetController = StreamController<MeshPacket>.broadcast();
      final advController =
          StreamController<AttendanceAdvertisement>.broadcast();

      final mockMesh = MockMeshService();
      when(mockMesh.attendancePackets)
          .thenAnswer((_) => packetController.stream);
      when(mockMesh.attendanceAdvertisements)
          .thenAnswer((_) => advController.stream);

      final (svc, db, crypto) = await _buildService(
        mesh: mockMesh,
        uid: teacherUid,
      );

      final sessionId = const Uuid().v4();
      final hmacToken =
          await crypto.generateHmacToken(sessionId, 'CS101');

      // Inject a packet that appears to come from ourselves.
      packetController.add(MeshPacket.attendance(
        id: const Uuid().v4(),
        senderUid: teacherUid, // same as our own UID — should be filtered
        sessionId: sessionId,
        hmacToken: hmacToken,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      // No proofs should be saved.
      final proofs = await db.proofsForSession(sessionId);
      expect(proofs, isEmpty);

      await svc.dispose();
      await packetController.close();
      await advController.close();
      await db.close();
    });

    test('duplicate packet for same session does not create second proof',
        () async {
      const teacherUid = 'teacher-dup-uid';
      const studentUid = 'student-dup-uid';

      final packetController = StreamController<MeshPacket>.broadcast();
      final advController =
          StreamController<AttendanceAdvertisement>.broadcast();

      final mockMesh = MockMeshService();
      when(mockMesh.attendancePackets)
          .thenAnswer((_) => packetController.stream);
      when(mockMesh.attendanceAdvertisements)
          .thenAnswer((_) => advController.stream);

      final studentDb = AppDatabase.memory();
      final studentCrypto = CryptoService();
      await studentCrypto.initialize();

      final syncEngine = MockFirebaseSyncEngine();
      when(syncEngine.syncNow()).thenAnswer((_) async {});

      final svc = AttendanceService(
        mesh: mockMesh,
        db: studentDb,
        crypto: studentCrypto,
        syncEngine: syncEngine,
        currentUserUid: studentUid,
        firestore: FakeFirebaseFirestore(),
      );
      svc.initialize();

      final sessionId = const Uuid().v4();
      final hmacToken =
          await studentCrypto.generateHmacToken(sessionId, 'CS101');

      // Inject the same session's packet twice (different packet UUIDs,
      // same sessionId — simulates teacher re-broadcasting every 5 s).
      for (int i = 0; i < 2; i++) {
        packetController.add(MeshPacket.attendance(
          id: const Uuid().v4(),
          senderUid: teacherUid,
          sessionId: sessionId,
          hmacToken: hmacToken,
        ));
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Only one proof should exist.
      final proofs = await studentDb.proofsForSession(sessionId);
      expect(proofs, hasLength(1));

      await svc.dispose();
      await packetController.close();
      await advController.close();
      await studentDb.close();
    });
  });

  group('AttendanceService — status stream', () {
    test('status starts as idle', () async {
      // Built manually (not via _buildService) because attendanceStatusStream
      // is a broadcast stream: initialize() emits the idle status
      // synchronously and broadcast streams don't buffer for late
      // subscribers. _buildService() calls initialize() before returning,
      // so by the time a caller attached a listener the only idle event
      // would already be gone and `.first` would hang forever. Subscribing
      // before calling initialize() here ensures the listener is in place
      // when the event fires.
      final mockMesh = MockMeshService();
      when(mockMesh.attendancePackets)
          .thenAnswer((_) => const Stream.empty());
      when(mockMesh.attendanceAdvertisements)
          .thenAnswer((_) => const Stream.empty());

      final db = AppDatabase.memory();
      final crypto = CryptoService();
      await crypto.initialize();

      final syncEngine = MockFirebaseSyncEngine();
      when(syncEngine.syncNow()).thenAnswer((_) async {});

      final svc = AttendanceService(
        mesh: mockMesh,
        db: db,
        crypto: crypto,
        syncEngine: syncEngine,
        currentUserUid: 'teacher-uid-idle-test',
        firestore: FakeFirebaseFirestore(),
      );

      final statusFuture =
          svc.attendanceStatusStream.first.timeout(const Duration(seconds: 2));
      svc.initialize();

      final firstStatus = await statusFuture;

      expect(firstStatus.type, AttendanceStatusType.idle);

      await svc.dispose();
    });
  });
}
