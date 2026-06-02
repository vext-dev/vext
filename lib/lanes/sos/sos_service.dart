// ── SosService — VEXT Lane C SOS Emergency ────────────────────────────────────
//
// Manages the full SOS lifecycle for ALL roles.
//
// ── Originator flow (any role) ────────────────────────────────────────────────
//   1. triggerSos(uid, lat, lng) →
//        - Builds MeshPacket.sos() with TTL=255.
//        - Sends via mesh.sendPacket() immediately.
//        - Writes SosRecord to Drift with synced=false.
//        - Calls syncEngine.syncNow() to push to Firestore immediately.
//        - Starts a Timer.periodic(2s) re-broadcast from THIS device.
//          (MeshService handles relay on intermediate nodes — we only need
//           re-broadcast for the originating device to keep flooding the mesh.)
//        - Emits SosStatus.active on sosStatusStream.
//
//   2. cancelSos() →
//        - Stops re-broadcast timer.
//        - Emits SosStatus.idle on sosStatusStream.
//
// ── Relay / receiver flow (all devices) ──────────────────────────────────────
//   1. Listens to mesh.sosPackets broadcast stream.
//   2. When a packet arrives from ANOTHER node:
//        - Decodes lat/lng from SOS payload.
//        - Skips if we have already processed this packet ID.
//        - Writes SosRecord to Drift.
//        - Calls syncEngine.syncNow() so Firestore gets it (triggers Cloud
//          Function → FCM to security devices).
//        - Emits on incomingSosStream (for SosScreen alert UI).
//
// ── GPS policy ────────────────────────────────────────────────────────────────
//   GPS is requested before triggering. If unavailable within 3 seconds,
//   fallback to (0.0, 0.0) with a visible warning. SOS is never blocked
//   by GPS unavailability.
//
// ── Re-broadcast note ─────────────────────────────────────────────────────────
//   MeshService._scheduleRelay() already relays incoming SOS packets with
//   zero-delay for TTL=255. SosService.re-broadcast only runs on the
//   ORIGINATING device to keep the mesh flooded while the event is active.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_constants.dart';
import '../../core/proto/mesh_packet.dart';
import '../../services/drift_service.dart';
import '../../services/firebase_sync_engine.dart';
import '../../services/mesh_service.dart';

// ── SosStatus ─────────────────────────────────────────────────────────────────

enum SosStatusType {
  idle,
  active,       // SOS triggered and re-broadcasting
  gpsWarning,   // SOS active but GPS was unavailable — sent with 0,0
}

class SosStatus {
  const SosStatus({
    required this.type,
    this.sosId,
    this.latitude,
    this.longitude,
    this.message,
  });

  const SosStatus.idle()
      : type = SosStatusType.idle,
        sosId = null,
        latitude = null,
        longitude = null,
        message = null;

  final SosStatusType type;
  final String? sosId;
  final double? latitude;
  final double? longitude;
  final String? message;
}

// ── IncomingSos ───────────────────────────────────────────────────────────────

/// Emitted on [SosService.incomingSosStream] when a remote SOS is received.
class IncomingSos {
  const IncomingSos({
    required this.packetId,
    required this.senderUid,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  final String packetId;
  final String senderUid;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
}

// ── SosService ─────────────────────────────────────────────────────────────────

class SosService {
  SosService({
    required MeshService mesh,
    required AppDatabase db,
    required FirebaseSyncEngine syncEngine,
    required String currentUserUid,
  })  : _mesh = mesh,
        _db = db,
        _syncEngine = syncEngine,
        _currentUserUid = currentUserUid;

  final MeshService _mesh;
  final AppDatabase _db;
  final FirebaseSyncEngine _syncEngine;
  final String _currentUserUid;

  // ── Active SOS state ───────────────────────────────────────────────────────
  String? _activeSosId;
  Timer? _rebroadcastTimer;
  MeshPacket? _activeSosPacket;

  // ── Dedup set ──────────────────────────────────────────────────────────────
  final Set<String> _processedPacketIds = {};

  // ── Stream controllers ─────────────────────────────────────────────────────
  final _statusController = StreamController<SosStatus>.broadcast();
  final _incomingController = StreamController<IncomingSos>.broadcast();

  /// Status updates for the originating device's SOS UI.
  Stream<SosStatus> get sosStatusStream => _statusController.stream;

  /// Incoming SOS packets from OTHER nodes — for security role UI.
  Stream<IncomingSos> get incomingSosStream => _incomingController.stream;

  bool get isActive => _activeSosId != null;

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<MeshPacket>? _packetSub;

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Wire mesh SOS stream. Call once after construction.
  void initialize() {
    _packetSub = _mesh.sosPackets.listen(_onSosPacket);
    _statusController.add(const SosStatus.idle());
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Trigger an SOS from this device.
  ///
  /// Attempts GPS first (3-second timeout). If GPS is unavailable, falls back
  /// to (0.0, 0.0) and emits [SosStatusType.gpsWarning] instead of
  /// [SosStatusType.active]. Either way the SOS is transmitted — GPS
  /// unavailability never blocks emergency transmission.
  Future<void> triggerSos() async {
    // Stop any previous SOS before starting a new one.
    if (isActive) await cancelSos();

    // ── GPS acquisition (best-effort, 3 s timeout) ─────────────────────────
    double latitude = 0.0;
    double longitude = 0.0;
    bool gpsOk = false;

    try {
      // Check / request permission.
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 3),
          ),
        );
        latitude = position.latitude;
        longitude = position.longitude;
        gpsOk = true;
      }
    } catch (_) {
      // Permission denied, service disabled, or timeout — use (0.0, 0.0).
    }

    final sosId = const Uuid().v4();
    _activeSosId = sosId;

    final packet = MeshPacket.sos(
      id: sosId,
      senderUid: _currentUserUid,
      latitude: latitude,
      longitude: longitude,
      ttl: AppConstants.ttlSos,
    );
    _activeSosPacket = packet;
    _processedPacketIds.add(sosId); // don't echo our own SOS back to UI

    // ── Send immediately ────────────────────────────────────────────────────
    await _mesh.sendPacket(packet);

    // ── Persist locally ─────────────────────────────────────────────────────
    await _db.upsertSosRecord(SosRecordsCompanion(
      id: Value(sosId),
      senderUid: Value(_currentUserUid),
      latitude: Value(latitude),
      longitude: Value(longitude),
      ttl: Value(AppConstants.ttlSos),
      timestamp: Value(DateTime.now()),
      synced: const Value(false),
    ));

    // ── Sync to Firestore — triggers handleSOSAlert Cloud Function ──────────
    _syncEngine.syncNow().ignore();

    // ── Re-broadcast timer (originating device only) ────────────────────────
    _rebroadcastTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.sosRebroadcastIntervalMs),
      (_) => _rebroadcast(),
    );

    // ── Emit status ─────────────────────────────────────────────────────────
    _statusController.add(SosStatus(
      type: gpsOk ? SosStatusType.active : SosStatusType.gpsWarning,
      sosId: sosId,
      latitude: latitude,
      longitude: longitude,
      message: gpsOk ? null : 'GPS unavailable — sending without location',
    ));
  }

  /// Cancel the active SOS re-broadcast.
  /// Does NOT retract the Firestore record — security staff should still see it.
  Future<void> cancelSos() async {
    _rebroadcastTimer?.cancel();
    _rebroadcastTimer = null;
    _activeSosId = null;
    _activeSosPacket = null;
    _statusController.add(const SosStatus.idle());
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await cancelSos();
    await _packetSub?.cancel();
    _statusController.close();
    _incomingController.close();
    _processedPacketIds.clear();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Re-send the active SOS packet (originating device only).
  void _rebroadcast() {
    final packet = _activeSosPacket;
    if (packet == null || _activeSosId == null) return;
    _mesh.sendPacket(packet).ignore();
  }

  /// Handle an incoming SOS packet from the mesh.
  void _onSosPacket(MeshPacket packet) {
    // Ignore our own broadcasts (looped back from mesh relay).
    if (packet.senderUid == _currentUserUid) return;

    // Deduplicate — mesh relay may deliver the same SOS multiple times.
    if (_processedPacketIds.contains(packet.id)) return;
    _processedPacketIds.add(packet.id);

    final coords = packet.decodeSosPayload();
    final lat = coords?.latitude ?? 0.0;
    final lng = coords?.longitude ?? 0.0;
    final now = DateTime.now();

    // Persist locally.
    _db.upsertSosRecord(SosRecordsCompanion(
      id: Value(packet.id),
      senderUid: Value(packet.senderUid),
      latitude: Value(lat),
      longitude: Value(lng),
      ttl: Value(packet.ttl),
      timestamp: Value(now),
      synced: const Value(false),
    )).ignore();

    // Sync to Firestore — triggers FCM Cloud Function for security nodes.
    _syncEngine.syncNow().ignore();

    // Notify UI.
    _incomingController.add(IncomingSos(
      packetId: packet.id,
      senderUid: packet.senderUid,
      latitude: lat,
      longitude: lng,
      timestamp: now,
    ));
  }
}
