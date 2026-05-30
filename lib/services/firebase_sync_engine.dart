// ── FirebaseSyncEngine — Offline-First Firestore Sync ──────────────────────────
//
// VEXT is designed to work without internet. All data written locally to Drift
// (SQLite) first. This engine runs opportunistically when connectivity is detected
// and uploads unsynced records in priority order.
//
// Sync priority:
//   1. SOS events     — highest priority (safety-critical)
//   2. Attendance proofs — medium priority
//   3. Messages       — lowest priority
//
// Firestore schema:
//   sos_events/{sosId}                    — SOS events
//   attendance/{sessionId}/proofs/{uid}   — Attendance proofs
//   messages/{threadId}/records/{id}      — Social messages
//
// Connectivity detection:
//   connectivity_plus ^6.x — onConnectivityChanged returns List<ConnectivityResult>
//
// NOTE: Firestore rules currently in test mode (wide-open).
//       Must be replaced with role-based rules BEFORE June 22, 2026 expiry.
//       See VEXT_Master_Tasks.md NOTE-5.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/app_constants.dart';
import '../services/drift_service.dart';

class FirebaseSyncEngine {
  FirebaseSyncEngine({
    required AppDatabase db,
    FirebaseFirestore? firestore,
  })  : _db = db,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final AppDatabase _db;
  final FirebaseFirestore _firestore;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncInProgress = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Start listening for connectivity changes and trigger sync on reconnect.
  /// Also runs an initial sync attempt in case we have connectivity already.
  Future<void> initialize() async {
    // Subscribe to connectivity changes.
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final hasNet = results.any((r) => r != ConnectivityResult.none);
        if (hasNet) {
          syncNow(); // ignore: unawaited_futures
        }
      },
    );

    // Try an immediate sync on startup.
    syncNow(); // ignore: unawaited_futures
  }

  /// Cancel the connectivity listener.
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Manually trigger a sync cycle. Safe to call while a sync is already
  /// in progress — the second call is silently ignored.
  Future<void> syncNow() async {
    if (_syncInProgress) return;
    _syncInProgress = true;

    try {
      await _syncSosEvents();
      await _syncAttendanceProofs();
      await _syncMessages();
    } catch (_) {
      // Network errors are expected (offline) — do not crash.
      // The next connectivity change will trigger another attempt.
    } finally {
      _syncInProgress = false;
    }
  }

  // ── SOS events — highest priority ─────────────────────────────────────────

  Future<void> _syncSosEvents() async {
    final records = await _db.unsyncedSosRecords();
    if (records.isEmpty) return;

    final batch = _firestore.batch();

    for (final record in records) {
      final ref = _firestore
          .collection(AppConstants.fsSosEvents)
          .doc(record.id);

      batch.set(ref, {
        'id':        record.id,
        'senderUid': record.senderUid,
        'latitude':  record.latitude,
        'longitude': record.longitude,
        'ttl':       record.ttl,
        'timestamp': Timestamp.fromDate(record.timestamp),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();

    // Mark all as synced.
    for (final record in records) {
      await _db.markSosSynced(record.id);
    }
  }

  // ── Attendance proofs ──────────────────────────────────────────────────────

  Future<void> _syncAttendanceProofs() async {
    final proofs = await _db.unsyncedAttendanceProofs();
    if (proofs.isEmpty) return;

    final batch = _firestore.batch();

    for (final proof in proofs) {
      final ref = _firestore
          .collection(AppConstants.fsAttendance)
          .doc(proof.sessionId)
          .collection(AppConstants.fsProofs)
          .doc(proof.studentUid);

      batch.set(ref, {
        'id':         proof.id,
        'sessionId':  proof.sessionId,
        'studentUid': proof.studentUid,
        'hmacToken':  proof.hmacToken,
        'rssi':       proof.rssi,
        'timestamp':  Timestamp.fromDate(proof.timestamp),
        'gpsLat':     proof.gpsLat,
        'gpsLng':     proof.gpsLng,
        'syncedAt':   FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();

    for (final proof in proofs) {
      await _db.markAttendanceProofSynced(proof.id);
    }
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Future<void> _syncMessages() async {
    final messages = await _db.unsyncedMessages();
    if (messages.isEmpty) return;

    final batch = _firestore.batch();

    for (final msg in messages) {
      // Thread ID: alphabetical sort of sender + recipient UIDs to keep
      // the same thread doc regardless of who initiates.
      // In Milestone 6 the recipient UID will be in the decrypted payload;
      // for now use senderUid as a placeholder thread ID.
      final threadId = msg.senderUid;

      final ref = _firestore
          .collection(AppConstants.fsMessages)
          .doc(threadId)
          .collection(AppConstants.fsRecords)
          .doc(msg.id);

      batch.set(ref, {
        'id':               msg.id,
        'senderUid':        msg.senderUid,
        'contentEncrypted': msg.contentEncrypted,
        'ttl':              msg.ttl,
        'timestamp':        Timestamp.fromDate(msg.timestamp),
        'lane':             msg.lane,
        'syncedAt':         FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();

    for (final msg in messages) {
      await _db.markMessageSynced(msg.id);
    }
  }
}
