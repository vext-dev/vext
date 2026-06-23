// ── MeshPacket — VEXT BLE Mesh Packet Encoding ────────────────────────────────
//
// Manual binary serialization compatible with the VEXT wire protocol.
// Does NOT use the protobuf code generator — avoids the protoc toolchain
// dependency for an academic project. The layout is protobuf-inspired
// (length-prefixed fields, fixed-width integers) but uses a custom tag scheme.
//
// Wire Format (little-endian throughout):
// ┌────────────────────────────────────────────────────────────────────────────┐
// │  Offset  │  Size  │  Field                                                │
// ├──────────┼────────┼───────────────────────────────────────────────────────┤
// │  0       │  1 B   │  type   (PacketType as uint8)                         │
// │  1       │  1 B   │  ttl    (uint8, 0-255)                                │
// │  2..17   │  16 B  │  packet_id  (UUID bytes, MSB first)                   │
// │  18..25  │  8 B   │  timestamp  (int64, milliseconds since Unix epoch)    │
// │  26      │  1 B   │  sender_uid length  (uint8, max 128 chars)            │
// │  27..N   │  var   │  sender_uid  (UTF-8, no null terminator)              │
// │  N+1..   │  rem   │  payload  (type-specific binary blob)                 │
// └────────────────────────────────────────────────────────────────────────────┘
//
// Total header (excluding sender_uid and payload): 27 bytes.
// BLE advertisement service data limit (legacy): ~20 bytes.
// → For advertisement: only type, ttl, packet_id are broadcast (18 bytes).
//   Full packet is exchanged via GATT in Milestone 3.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

// ── PacketType ─────────────────────────────────────────────────────────────────

enum PacketType {
  attendance(0x01),
  message(0x02),
  sos(0x03),
  ack(0x04),
  // Milestone 7 — 1:1 encrypted direct message (Lane B). Kept as a brand-new
  // type rather than extending `message`'s payload: the existing message
  // payload is unstructured raw UTF-8 text with no length prefix, so any
  // node that doesn't recognise an appended field would misinterpret the
  // extra bytes as message text. A new type fails closed instead — old
  // nodes simply don't recognise 0x05 (PacketType.fromWire returns null,
  // MeshPacket.fromBytes discards the whole packet) rather than corrupting
  // a decode. Relay logic is entirely type-agnostic (see MeshService
  // _scheduleRelay), so directMessage packets relay correctly with zero
  // changes there.
  directMessage(0x05);

  const PacketType(this.wireValue);

  /// Single byte written to the wire.
  final int wireValue;

  /// Deserialize from a wire byte. Returns null for unknown types.
  static PacketType? fromWire(int value) {
    for (final t in values) {
      if (t.wireValue == value) return t;
    }
    return null;
  }
}

// ── MeshPacket ─────────────────────────────────────────────────────────────────

class MeshPacket {
  MeshPacket({
    required this.id,
    required this.type,
    required this.ttl,
    required this.senderUid,
    required this.timestamp,
    this.payload = const [],
  });

  /// UUID v4 string (36 chars with hyphens). Globally unique in the mesh.
  final String id;

  /// Packet type — determines how the payload is decoded.
  final PacketType type;

  /// Remaining relay hops. Each forwarding node decrements by 1.
  /// At 0: do not relay. Maximum: 255 (SOS).
  final int ttl;

  /// Firebase UID of the originating node.
  final String senderUid;

  /// When the originating node created this packet.
  final DateTime timestamp;

  /// Type-specific binary payload (empty for ACK packets).
  final List<int> payload;

  // ── Derived / helpers ──────────────────────────────────────────────────────

  /// True if this packet has exceeded its relay budget.
  bool get isExpired => ttl <= 0;

  /// Return a copy with TTL decremented by 1 — call before relaying.
  MeshPacket decrementTtl() => MeshPacket(
        id: id,
        type: type,
        ttl: (ttl - 1).clamp(0, 255),
        senderUid: senderUid,
        timestamp: timestamp,
        payload: payload,
      );

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Encode to bytes for BLE advertisement service data or GATT transfer.
  Uint8List toBytes() {
    final uidBytes = utf8.encode(senderUid);
    final uidLen = uidBytes.length.clamp(0, 255);

    final idBytes = _uuidToBytes(id);
    final tsMs = timestamp.millisecondsSinceEpoch;

    // Total size: 1 (type) + 1 (ttl) + 16 (uuid) + 8 (ts) + 1 (uid_len)
    //           + uidLen + payload.length
    final buf = ByteData(27 + uidLen + payload.length);
    int offset = 0;

    buf.setUint8(offset++, type.wireValue);
    buf.setUint8(offset++, ttl.clamp(0, 255));

    for (final b in idBytes) {
      buf.setUint8(offset++, b);
    }

    buf.setInt64(offset, tsMs, Endian.little);
    offset += 8;

    buf.setUint8(offset++, uidLen);

    for (int i = 0; i < uidLen; i++) {
      buf.setUint8(offset++, uidBytes[i]);
    }

    for (final b in payload) {
      buf.setUint8(offset++, b);
    }

    return buf.buffer.asUint8List();
  }

  /// Decode bytes produced by [toBytes]. Returns null on malformed input.
  static MeshPacket? fromBytes(Uint8List bytes) {
    try {
      if (bytes.length < 27) return null;

      final buf = ByteData.sublistView(bytes);
      int offset = 0;

      final typeRaw = buf.getUint8(offset++);
      final packetType = PacketType.fromWire(typeRaw);
      if (packetType == null) return null;

      final ttl = buf.getUint8(offset++);

      final idBytes = bytes.sublist(offset, offset + 16);
      offset += 16;
      final id = _bytesToUuid(idBytes);

      final tsMs = buf.getInt64(offset, Endian.little);
      offset += 8;
      final timestamp =
          DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true).toLocal();

      final uidLen = buf.getUint8(offset++);
      if (offset + uidLen > bytes.length) return null;

      final senderUid =
          utf8.decode(bytes.sublist(offset, offset + uidLen));
      offset += uidLen;

      final payload = offset < bytes.length
          ? bytes.sublist(offset).toList()
          : const <int>[];

      return MeshPacket(
        id: id,
        type: packetType,
        ttl: ttl,
        senderUid: senderUid,
        timestamp: timestamp,
        payload: payload,
      );
    } catch (_) {
      return null; // Malformed — caller should discard packet
    }
  }

  // ── Advertisement subset ───────────────────────────────────────────────────
  //
  // The full packet is too large for a BLE legacy advertisement (≤27 bytes
  // service data). We broadcast only the minimal 18-byte header for dedup
  // and routing decisions. Full payload is fetched via GATT (Milestone 3).

  /// 18-byte advertisement payload: type(1) + ttl(1) + uuid(16).
  Uint8List toAdvertisementBytes() {
    final idBytes = _uuidToBytes(id);
    final buf = Uint8List(18);
    buf[0] = type.wireValue;
    buf[1] = ttl.clamp(0, 255);
    for (int i = 0; i < 16; i++) {
      buf[2 + i] = idBytes[i];
    }
    return buf;
  }

  /// Parse the 18-byte advertisement subset (no senderUid / payload).
  /// Used during BLE scanning to decide whether to fetch the full packet.
  static MeshPacket? fromAdvertisementBytes(Uint8List bytes) {
    if (bytes.length < 18) return null;
    final typeRaw = bytes[0];
    final packetType = PacketType.fromWire(typeRaw);
    if (packetType == null) return null;
    final ttl = bytes[1];
    final id = _bytesToUuid(bytes.sublist(2, 18));
    return MeshPacket(
      id: id,
      type: packetType,
      ttl: ttl,
      senderUid: '', // unknown until GATT fetch
      timestamp: DateTime.now(),
    );
  }

  // ── UUID byte helpers ──────────────────────────────────────────────────────

  /// Encode "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" into 16 bytes (MSB first).
  static List<int> _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    if (hex.length != 32) return List.filled(16, 0);
    final bytes = <int>[];
    for (int i = 0; i < 32; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Decode 16 bytes back to "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
  static String _bytesToUuid(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  // ── Payload constructors (typed helpers) ───────────────────────────────────
  //
  // Each lane (Attendance/Message/SOS) has its own payload layout.
  // These factories make it easy to build type-correct packets.

  /// Build an attendance announcement packet.
  /// [sessionId]    : UUID of the active session (teacher-side)
  /// [hmacToken]    : 32-char hex HMAC-SHA256 proving temporal presence
  /// [geofenceLat]/[geofenceLng] : teacher's GPS fix at session start
  ///   (Milestone 7 geofence center) — optional. Null when the teacher's
  ///   device had no GPS fix; the student-side geofence check is then
  ///   skipped entirely for this session (RSSI remains the sole gate).
  factory MeshPacket.attendance({
    required String id,
    required String senderUid,
    required String sessionId,
    required String hmacToken,
    double? geofenceLat,
    double? geofenceLng,
    int ttl = 5, // AppConstants.ttlAttendance
  }) {
    final sessionIdBytes = utf8.encode(sessionId);
    final hmacBytes = utf8.encode(hmacToken);

    // GPS geofence center — appended AFTER the original Milestone 4 fields
    // with a 1-byte presence flag. This keeps the wire format backward- and
    // forward-compatible without a version bump: decodeAttendancePayload()
    // only looks for the flag byte if any bytes remain past the HMAC token,
    // so a packet built without GPS (flag omitted entirely) decodes exactly
    // as it did before this field existed.
    final hasGeofence = geofenceLat != null && geofenceLng != null;

    // Payload: 1 (session_id_len) + sessionIdLen + 1 (hmac_len) + hmacLen
    //        + 1 (gps_present flag) + [16 if hasGeofence]
    final buf = ByteData(
      2 +
          sessionIdBytes.length +
          hmacBytes.length +
          1 +
          (hasGeofence ? 16 : 0),
    );
    int offset = 0;
    buf.setUint8(offset++, sessionIdBytes.length);
    for (final b in sessionIdBytes) {
      buf.setUint8(offset++, b);
    }
    buf.setUint8(offset++, hmacBytes.length);
    for (final b in hmacBytes) {
      buf.setUint8(offset++, b);
    }
    buf.setUint8(offset++, hasGeofence ? 1 : 0);
    if (geofenceLat != null && geofenceLng != null) {
      buf.setFloat64(offset, geofenceLat, Endian.little);
      offset += 8;
      buf.setFloat64(offset, geofenceLng, Endian.little);
      offset += 8;
    }

    return MeshPacket(
      id: id,
      type: PacketType.attendance,
      ttl: ttl,
      senderUid: senderUid,
      timestamp: DateTime.now(),
      payload: buf.buffer.asUint8List().toList(),
    );
  }

  /// Build a social message packet.
  /// [contentEncrypted] : UTF-8 text in Milestone 2; ciphertext in Milestone 3.
  factory MeshPacket.message({
    required String id,
    required String senderUid,
    required String contentEncrypted,
    int ttl = 7, // AppConstants.ttlMessage
  }) {
    return MeshPacket(
      id: id,
      type: PacketType.message,
      ttl: ttl,
      senderUid: senderUid,
      timestamp: DateTime.now(),
      payload: utf8.encode(contentEncrypted),
    );
  }

  /// Build an SOS packet.
  /// [latitude] / [longitude] : GPS fix at time of SOS trigger.
  factory MeshPacket.sos({
    required String id,
    required String senderUid,
    required double latitude,
    required double longitude,
    int ttl = 255, // AppConstants.ttlSos
  }) {
    final buf = ByteData(16); // 2 × float64
    buf.setFloat64(0, latitude, Endian.little);
    buf.setFloat64(8, longitude, Endian.little);

    return MeshPacket(
      id: id,
      type: PacketType.sos,
      ttl: ttl,
      senderUid: senderUid,
      timestamp: DateTime.now(),
      payload: buf.buffer.asUint8List().toList(),
    );
  }

  // ── Attendance ACK (Fix 4A) ────────────────────────────────────────────────
  //
  // After a student marks attendance via GATT, they send an ACK packet back
  // to the mesh. The teacher's AttendanceService listens to ackPackets and
  // writes the proof to its local Drift DB, enabling an offline dashboard.
  //
  // ACK payload layout (little-endian):
  //   1 B   session_id_len
  //   var   session_id (UTF-8)
  //   1 B   hmac_len
  //   var   hmacToken (UTF-8)
  //   4 B   rssi (int32) — effective RSSI from the student's proof assembly

  /// Build an attendance ACK packet sent by the student after marking present.
  ///
  /// [senderUid]  : studentUid — already in the packet header, no need to repeat.
  /// [sessionId]  : session the student just marked attendance for.
  /// [hmacToken]  : the HMAC token from the teacher's attendance packet.
  /// [rssi]       : the effective RSSI recorded in the student's proof.
  /// [ttl]        : kept short (3) — ACK only needs to reach the teacher node.
  factory MeshPacket.attendanceAck({
    required String id,
    required String senderUid,
    required String sessionId,
    required String hmacToken,
    required int rssi,
    int ttl = 3,
  }) {
    final sessionIdBytes = utf8.encode(sessionId);
    final hmacBytes = utf8.encode(hmacToken);

    // Payload: 1 (session_id_len) + sessionIdLen + 1 (hmac_len) + hmacLen + 4 (rssi)
    final buf = ByteData(2 + sessionIdBytes.length + hmacBytes.length + 4);
    int offset = 0;
    buf.setUint8(offset++, sessionIdBytes.length);
    for (final b in sessionIdBytes) {
      buf.setUint8(offset++, b);
    }
    buf.setUint8(offset++, hmacBytes.length);
    for (final b in hmacBytes) {
      buf.setUint8(offset++, b);
    }
    buf.setInt32(offset, rssi, Endian.little);

    return MeshPacket(
      id: id,
      type: PacketType.ack,
      ttl: ttl,
      senderUid: senderUid,
      timestamp: DateTime.now(),
      payload: buf.buffer.asUint8List().toList(),
    );
  }

  // ── Direct message (Milestone 7) ───────────────────────────────────────────
  //
  // Payload layout (little-endian):
  //   1 B   recipient_uid_len
  //   var   recipient_uid (UTF-8)
  //   var   encryptedBytes — flat nonce(12) + mac(16) + ciphertext(N),
  //         exactly EncryptedMessage.toBytes()'s layout (crypto_service.dart).
  //         Carried as opaque bytes here; CryptoService owns en/decryption.
  //
  // Relay nodes forward this packet regardless of recipientUid — addressing
  // is handled at the application layer (SocialService), not the mesh layer.
  // Only the node whose own UID matches recipientUid will attempt to decrypt.

  /// Build a 1:1 encrypted direct message packet.
  /// [recipientUid]    : Firebase UID of the intended recipient.
  /// [encryptedBytes]  : output of EncryptedMessage.toBytes() — the caller
  ///   (SocialService) is responsible for calling CryptoService.encryptMessage
  ///   first and passing the serialised result here.
  factory MeshPacket.directMessage({
    required String id,
    required String senderUid,
    required String recipientUid,
    required List<int> encryptedBytes,
    int ttl = 7, // AppConstants.ttlMessage
  }) {
    final recipientBytes = utf8.encode(recipientUid);
    final recipientLen = recipientBytes.length.clamp(0, 255);

    final buf = ByteData(1 + recipientLen + encryptedBytes.length);
    int offset = 0;
    buf.setUint8(offset++, recipientLen);
    for (final b in recipientBytes) {
      buf.setUint8(offset++, b);
    }
    for (final b in encryptedBytes) {
      buf.setUint8(offset++, b);
    }

    return MeshPacket(
      id: id,
      type: PacketType.directMessage,
      ttl: ttl,
      senderUid: senderUid,
      timestamp: DateTime.now(),
      payload: buf.buffer.asUint8List().toList(),
    );
  }

  // ── Payload decoders ───────────────────────────────────────────────────────

  /// Extract sessionId, hmacToken, and (if present) the teacher's GPS
  /// geofence center from an attendance packet's payload.
  /// Returns null if the payload is malformed.
  ({
    String sessionId,
    String hmacToken,
    double? geofenceLat,
    double? geofenceLng,
  })? decodeAttendancePayload() {
    if (type != PacketType.attendance) return null;
    try {
      final buf = ByteData.sublistView(Uint8List.fromList(payload));
      int offset = 0;
      final sessionLen = buf.getUint8(offset++);
      final sessionId =
          utf8.decode(payload.sublist(offset, offset + sessionLen));
      offset += sessionLen;
      final hmacLen = buf.getUint8(offset++);
      final hmacToken =
          utf8.decode(payload.sublist(offset, offset + hmacLen));
      offset += hmacLen;

      // GPS geofence center (teacher's location at session start) — optional,
      // appended after the original Milestone 4 fields with a 1-byte presence
      // flag. A packet built before this field existed, or one where the
      // teacher's device had no GPS fix, simply ends here
      // (offset == payload.length): this block is skipped and both values
      // stay null, identical to the pre-geofence decode result.
      double? geofenceLat;
      double? geofenceLng;
      if (offset < payload.length) {
        final gpsPresent = buf.getUint8(offset++);
        if (gpsPresent == 1 && offset + 16 <= payload.length) {
          geofenceLat = buf.getFloat64(offset, Endian.little);
          offset += 8;
          geofenceLng = buf.getFloat64(offset, Endian.little);
          offset += 8;
        }
      }

      return (
        sessionId: sessionId,
        hmacToken: hmacToken,
        geofenceLat: geofenceLat,
        geofenceLng: geofenceLng,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extract message content from a message packet's payload.
  String? decodeMessageContent() {
    if (type != PacketType.message) return null;
    try {
      return utf8.decode(payload);
    } catch (_) {
      return null;
    }
  }

  /// Extract GPS coordinates from an SOS packet's payload.
  ({double latitude, double longitude})? decodeSosPayload() {
    if (type != PacketType.sos || payload.length < 16) return null;
    try {
      final buf = ByteData.sublistView(Uint8List.fromList(payload));
      return (
        latitude: buf.getFloat64(0, Endian.little),
        longitude: buf.getFloat64(8, Endian.little),
      );
    } catch (_) {
      return null;
    }
  }

  /// Extract sessionId, hmacToken, and rssi from an attendanceAck payload.
  ///
  /// Returns null if the packet is not an ACK or the payload is malformed.
  /// Used by the teacher's AttendanceService to build a local Drift proof.
  ({String sessionId, String hmacToken, int rssi})? decodeAttendanceAckPayload() {
    if (type != PacketType.ack || payload.isEmpty) return null;
    try {
      final data = Uint8List.fromList(payload);
      final buf = ByteData.sublistView(data);
      int offset = 0;

      final sessionLen = buf.getUint8(offset++);
      if (offset + sessionLen > data.length) return null;
      final sessionId = utf8.decode(data.sublist(offset, offset + sessionLen));
      offset += sessionLen;

      final hmacLen = buf.getUint8(offset++);
      if (offset + hmacLen + 4 > data.length) return null;
      final hmacToken = utf8.decode(data.sublist(offset, offset + hmacLen));
      offset += hmacLen;

      final rssi = buf.getInt32(offset, Endian.little);
      return (sessionId: sessionId, hmacToken: hmacToken, rssi: rssi);
    } catch (_) {
      return null;
    }
  }

  /// Extract recipientUid + raw encrypted bytes from a directMessage
  /// packet's payload. The encrypted bytes are passed to
  /// `EncryptedMessage.fromBytes()` (crypto_service.dart) to recover the
  /// nonce/mac/ciphertext for `CryptoService.decryptMessage()`.
  /// Returns null if the payload is malformed or this is not a
  /// directMessage packet.
  ({String recipientUid, Uint8List encryptedBytes})?
      decodeDirectMessagePayload() {
    if (type != PacketType.directMessage) return null;
    try {
      final data = Uint8List.fromList(payload);
      final buf = ByteData.sublistView(data);
      int offset = 0;
      final recipientLen = buf.getUint8(offset++);
      if (offset + recipientLen > data.length) return null;
      final recipientUid =
          utf8.decode(data.sublist(offset, offset + recipientLen));
      offset += recipientLen;
      final encryptedBytes = data.sublist(offset);
      return (recipientUid: recipientUid, encryptedBytes: encryptedBytes);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'MeshPacket(id: ${id.substring(0, 8)}…, type: $type, ttl: $ttl, '
      'sender: ${senderUid.isNotEmpty ? senderUid.substring(0, 4) : "?"} …)';
}
