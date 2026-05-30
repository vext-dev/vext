/// All application-wide constants for VEXT VigilantMesh.
/// No magic numbers anywhere else in the codebase — reference these.
abstract class AppConstants {
  // ── BLE Service UUIDs ─────────────────────────────────────────────────────
  /// Primary service UUID for VEXT mesh packets.
  static const String bleServiceUuid =
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Characteristic UUID for mesh packet data.
  static const String bleCharacteristicUuid =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  // ── RSSI Thresholds ───────────────────────────────────────────────────────
  /// Default RSSI threshold for attendance verification (-75 dBm ≈ 8-10 m).
  static const int rssiThresholdDefault = -75;

  /// Minimum RSSI to consider a peer "nearby" for mesh relay.
  static const int rssiMeshMinimum = -90;

  // ── TTL Values ────────────────────────────────────────────────────────────
  /// TTL for regular social messages (Lane B) — ~50-80 m range.
  static const int ttlMessage = 7;

  /// TTL for attendance packets (Lane A).
  static const int ttlAttendance = 5;

  /// TTL for SOS packets (Lane C) — effectively unlimited.
  static const int ttlSos = 255;

  // ── Timing Constants ──────────────────────────────────────────────────────
  /// HMAC token validity window in seconds (90 s rolling window).
  static const int hmacWindowSeconds = 90;

  /// Attendance advertisement interval in milliseconds.
  static const int attendanceAdvertiseIntervalMs = 5000;

  /// SOS re-broadcast interval in milliseconds.
  static const int sosRebroadcastIntervalMs = 2000;

  /// SOS max broadcast duration before fallback (5 minutes).
  static const int sosMaxBroadcastMs = 300000;

  // ── Duty Cycle ────────────────────────────────────────────────────────────
  /// Active scan period (ms) in default idle mode.
  static const int dutyCycleActiveMsIdle = 1000;

  /// Sleep period (ms) in default idle mode (3% duty cycle).
  static const int dutyCycleSleepMsIdle = 30000;

  /// Active scan period (ms) during active session (Lane A).
  static const int dutyCycleActiveMsSession = 500;

  /// Sleep period (ms) during active session.
  static const int dutyCycleSleepMsSession = 500;

  /// Active scan period (ms) during SOS mode — maximum scan rate.
  static const int dutyCycleActiveMsSos = 100;

  /// Sleep period (ms) during SOS mode.
  static const int dutyCycleSleepMsSos = 100;

  // ── Exponential Backoff ───────────────────────────────────────────────────
  /// Base delay (ms) for exponential backoff relay.
  static const int backoffBaseMs = 50;

  /// Maximum delay (ms) for exponential backoff relay.
  static const int backoffMaxMs = 500;

  // ── Database Purge Policies ───────────────────────────────────────────────
  /// How long to keep SeenPacket entries (60 minutes).
  static const Duration seenTableTtl = Duration(minutes: 60);

  /// How long to keep MessageRecord entries (30 days).
  static const Duration messageRetention = Duration(days: 30);

  /// How long to keep PeerTable entries without seeing peer (7 days).
  static const Duration peerRetention = Duration(days: 7);

  // ── GPS ───────────────────────────────────────────────────────────────────
  /// Default GPS geofence radius in metres for attendance.
  static const double geofenceRadiusDefault = 50.0;

  /// Minimum GPS accuracy threshold to use the fix (metres).
  static const double gpsMinAccuracyMetres = 50.0;

  // ── Foreground Service ────────────────────────────────────────────────────
  static const int foregroundServiceNotificationId = 1001;
  static const String foregroundServiceChannelId = 'vext_mesh_channel';
  static const String foregroundServiceChannelName = 'VigilantMesh Service';
  static const String foregroundServiceNotificationTitle = 'VEXT VigilantMesh';
  static const String foregroundServiceNotificationBody =
      'Listening for campus events…';

  // ── Firestore Collections ─────────────────────────────────────────────────
  static const String fsUsers = 'users';
  static const String fsInstitutions = 'institutions';
  static const String fsSessions = 'sessions';
  static const String fsAttendance = 'attendance';
  static const String fsProofs = 'proofs';
  static const String fsMessages = 'messages';
  static const String fsRecords = 'records';
  static const String fsSosEvents = 'sos_events';

  // ── Firebase Cloud Function names ─────────────────────────────────────────
  static const String fnHandleSosAlert = 'handleSOSAlert';
  static const String fnAggregateAttendance = 'aggregateAttendance';
  static const String fnRotatePeerKeys = 'rotatePeerKeys';

  // ── User Roles ────────────────────────────────────────────────────────────
  static const String roleStudent = 'student';
  static const String roleTeacher = 'teacher';
  static const String roleSecurity = 'security';
}
