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
// ── Why we do NOT use waitForPendingWrites() ───────────────────────────────────
//
// waitForPendingWrites() is a GLOBAL call — it waits for every pending Firestore
// write from the current user session, not just the writes from this batch.
// This includes fire-and-forget writes from saveFcmToken(), profile updates, etc.
//
// If ANY of those unrelated writes is slow or rejected by a security rule, our
// batch's markAttendanceProofSynced() call is also blocked or skipped. The proof
// stays synced=false, and because _needsRetry only fires on connectivity changes
// (not on a timer), the proof is permanently lost on stable WiFi.
//
// The correct approach: trust Firestore offline persistence. batch.commit() writes
// to local cache AND queues for immediate server delivery. The Firestore SDK
// automatically delivers the write to the server when online — no manual
// verification needed. The teacher's snapshots() listener updates when the write
// reaches the server. markAttendanceProofSynced() after batch.commit() is the
// correct, reliable pattern.
//
// For genuine failures (batch.commit() itself throws), the per-category try-catch
// in syncNow() sets _needsRetry=true, and the retry timer fires after 10s.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async' show StreamSubscription, Timer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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

  // Set to true when any sync category fails. Triggers a retry timer (10 s)
  // and is also consumed by the connectivity listener.
  bool _needsRetry = false;

  // Retry timer — fires 10 s after a sync failure to re-attempt without
  // needing a connectivity change. Cancelled if a sync succeeds first.
  Timer? _retryTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Start listening for connectivity changes and trigger sync on reconnect.
  /// Also runs an initial sync attempt in case we have connectivity already.
  Future<void> initialize() async {
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final hasNet = results.any((r) => r != ConnectivityResult.none);
        if (hasNet || _needsRetry) {
          debugPrint('[SyncEngine] connectivity changed '
              '(hasNet=$hasNet, needsRetry=$_needsRetry) — triggering sync');
          syncNow().ignore();
        }
      },
    );

    // Try an immediate sync on startup.
    syncNow().ignore();
  }

  /// Cancel the connectivity listener and any pending retry timer.
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Manually trigger a sync cycle. Safe to call while a sync is already
  /// in progress — the second call is silently ignored.
  Future<void> syncNow() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    _needsRetry = false;

    // Cancel any pending retry timer — this sync covers it.
    _retryTimer?.cancel();
    _retryTimer = null;

    debugPrint('[SyncEngine] syncNow() started');

    try {
      // Each category is independent — a failure in one does NOT block the
      // others. All three always run even if one throws.
      try {
        await _syncSosEvents();
      } catch (e) {
        debugPrint('[SyncEngine] _syncSosEvents failed: $e');
        _needsRetry = true;
      }

      try {
        await _syncAttendanceProofs();
      } catch (e) {
        debugPrint('[SyncEngine] _syncAttendanceProofs failed: $e');
        _needsRetry = true;
      }

      try {
        await _syncMessages();
      } catch (e) {
        debugPrint('[SyncEngine] _syncMessages failed: $e');
        _needsRetry = true;
      }

      debugPrint('[SyncEngine] syncNow() done — needsRetry=$_needsRetry');

      // Schedule a retry timer if any category failed. This handles transient
      // failures (momentary server hiccup, temporary rule issue) without
      // requiring the user to toggle WiFi to trigger the connectivity listener.
      if (_needsRetry) {
        _retryTimer = Timer(const Duration(seconds: 10), () {
          _retryTimer = null;
          debugPrint('[SyncEngine] retry timer fired — re-attempting sync');
          syncNow().ignore();
        });
      }
    } finally {
      // Always unset the guard — even if something unexpected escapes the
      // per-category catches above.
      _syncInProgress = false;
    }
  }

  // ── SOS events — highest priority ─────────────────────────────────────────

  Future<void> _syncSosEvents() async {
    final records = await _db.unsyncedSosRecords();
    if (records.isEmpty) return;

    debugPrint('[SyncEngine] uploading ${records.length} SOS event(s)');

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

    for (final record in records) {
      await _db.markSosSynced(record.id);
    }
    debugPrint('[SyncEngine] ${records.length} SOS event(s) queued for delivery');
  }

  // ── Attendance proofs ──────────────────────────────────────────────────────

  Future<void> _syncAttendanceProofs() async {
    final proofs = await _db.unsyncedAttendanceProofs();
    if (proofs.isEmpty) return;

    debugPrint('[SyncEngine] uploading ${proofs.length} attendance proof(s)');

    final batch = _firestore.batch();

    for (final proof in proofs) {
      final ref = _firestore
          .collection(AppConstants.fsAttendance)
          .doc(proof.sessionId)
          .collection(AppConstants.fsProofs)
          .doc(proof.studentUid);

      debugPrint('[SyncEngine] proof → '
          'attendance/${proof.sessionId}/proofs/${proof.studentUid}');

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

    // batch.commit() with Firestore offline persistence:
    //
    //   ONLINE: writes go to the local cache and are queued for immediate
    //           server upload. The SDK delivers them within milliseconds.
    //           The teacher's snapshots() listener on the proof collection
    //           receives the update automatically — no further action needed.
    //
    //   OFFLINE: writes go to the local cache and are queued. The SDK delivers
    //            them automatically when connectivity is restored. The teacher's
    //            listener updates at that point.
    //
    // markAttendanceProofSynced() is called immediately after batch.commit()
    // so Drift does not re-upload the same proof on the next sync cycle. This
    // is safe because Firestore offline persistence guarantees delivery.
    //
    // IMPORTANT: Do NOT add waitForPendingWrites() here. That call is global —
    // it blocks on ALL pending Firestore writes (FCM tokens, profile updates,
    // etc.) and throws if any of them fail. When it throws, markSynced() is
    // skipped, the proof stays synced=false, and the teacher never sees the
    // student. See the file header for the full explanation.
    await batch.commit();

    for (final proof in proofs) {
      await _db.markAttendanceProofSynced(proof.id);
    }

    debugPrint('[SyncEngine] ${proofs.length} attendance proof(s) queued for '
        'Firestore delivery — teacher will see student once server confirms');
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Future<void> _syncMessages() async {
    final messages = await _db.unsyncedMessages();
    if (messages.isEmpty) return;

    debugPrint('[SyncEngine] uploading ${messages.length} message(s)');

    final batch = _firestore.batch();

    for (final msg in messages) {
      // All social messages go to the shared 'broadcast' thread so every
      // authenticated user's Firestore subscription can read them (BUG C4 fixed).
      const threadId = 'broadcast';

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
    debugPrint('[SyncEngine] ${messages.length} message(s) queued for delivery');
  }
}
