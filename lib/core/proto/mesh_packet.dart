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
  ack(0x04);

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
  /// [sessionId]  : UUID of the active session (teacher-side)
  /// [hmacToken]  : 32-char hex HMAC-SHA256 proving temporal presence
  factory MeshPacket.attendance({
    required String id,
    required String senderUid,
    required String sessionId,
    required String hmacToken,
    int ttl = 5, // AppConstants.ttlAttendance
  }) {
    final sessionIdBytes = utf8.encode(sessionId);
    final hmacBytes = utf8.encode(hmacToken);

    // Payload: 1 (session_id_len) + sessionIdLen + 1 (hmac_len) + hmacLen
    final buf = ByteData(2 + sessionIdBytes.length + hmacBytes.length);
    int offset = 0;
    buf.setUint8(offset++, sessionIdBytes.length);
    for (final b in sessionIdBytes) buf.setUint8(offset++, b);
    buf.setUint8(offset++, hmacBytes.length);
    for (final b in hmacBytes) buf.setUint8(offset++, b);

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

  // ── Payload decoders ───────────────────────────────────────────────────────

  /// Extract sessionId and hmacToken from an attendance packet's payload.
  /// Returns null if the payload is malformed.
  ({String sessionId, String hmacToken})? decodeAttendancePayload() {
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
      return (sessionId: sessionId, hmacToken: hmacToken);
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

  @override
  String toString() =>
      'MeshPacket(id: ${id.substring(0, 8)}…, type: $type, ttl: $ttl, '
      'sender: ${senderUid.isNotEmpty ? senderUid.substring(0, 4) : "?"} …)';
}
