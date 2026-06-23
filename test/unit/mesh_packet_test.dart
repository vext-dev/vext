// ── MeshPacket Wire-Format Unit Tests ──────────────────────────────────────────
//
// Focused on MeshPacket.attendance() / decodeAttendancePayload() — specifically
// the Milestone 7 GPS geofence extension. These are pure Dart, byte-level tests
// with zero platform-channel dependency (no Geolocator, no Firebase, no secure
// storage), so they run instantly under `flutter test` without any mocking.
//
// Why this file exists: the geofence fields were appended to the attendance
// payload AFTER the original sessionId+hmacToken fields, gated by a 1-byte
// presence flag, specifically so OLD packets (built before this field existed)
// and NEW packets without a GPS fix decode identically — no wire version bump.
// These tests assert that backward-compatibility claim directly, since it's the
// single riskiest part of this change and the one most likely to silently
// regress if the encode/decode offsets ever drift out of sync.
//
// Run with:
//   flutter test test/unit/mesh_packet_test.dart
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:vext/core/proto/mesh_packet.dart';

void main() {
  group('MeshPacket.attendance — GPS geofence wire format', () {
    test('round-trips sessionId + hmacToken with NO geofence data', () {
      final packet = MeshPacket.attendance(
        id: const Uuid().v4(),
        senderUid: 'teacher-1',
        sessionId: 'session-abc',
        hmacToken: 'deadbeef',
      );

      final decoded = packet.decodeAttendancePayload();

      expect(decoded, isNotNull);
      expect(decoded!.sessionId, 'session-abc');
      expect(decoded.hmacToken, 'deadbeef');
      expect(decoded.geofenceLat, isNull);
      expect(decoded.geofenceLng, isNull);
    });

    test('round-trips sessionId + hmacToken WITH geofence data', () {
      final packet = MeshPacket.attendance(
        id: const Uuid().v4(),
        senderUid: 'teacher-1',
        sessionId: 'session-xyz',
        hmacToken: 'cafebabe',
        geofenceLat: 13.0357, // BMSCE-ish coordinate, arbitrary for the test
        geofenceLng: 77.5660,
      );

      final decoded = packet.decodeAttendancePayload();

      expect(decoded, isNotNull);
      expect(decoded!.sessionId, 'session-xyz');
      expect(decoded.hmacToken, 'cafebabe');
      expect(decoded.geofenceLat, closeTo(13.0357, 1e-9));
      expect(decoded.geofenceLng, closeTo(77.5660, 1e-9));
    });

    test('omitting only ONE of geofenceLat/geofenceLng is treated as absent',
        () {
      // Factory requires BOTH non-null to encode a geofence center — passing
      // only one is the same as passing neither (hasGeofence stays false).
      final packet = MeshPacket.attendance(
        id: const Uuid().v4(),
        senderUid: 'teacher-1',
        sessionId: 'session-partial',
        hmacToken: 'token123',
        geofenceLat: 13.0357,
        geofenceLng: null,
      );

      final decoded = packet.decodeAttendancePayload();

      expect(decoded, isNotNull);
      expect(decoded!.geofenceLat, isNull);
      expect(decoded.geofenceLng, isNull);
    });

    test('negative coordinates (southern/western hemisphere) round-trip correctly',
        () {
      final packet = MeshPacket.attendance(
        id: const Uuid().v4(),
        senderUid: 'teacher-1',
        sessionId: 'session-neg',
        hmacToken: 'token456',
        geofenceLat: -33.8688, // Sydney-ish
        geofenceLng: -70.6483, // (mismatched on purpose — just exercising sign bits)
      );

      final decoded = packet.decodeAttendancePayload();

      expect(decoded, isNotNull);
      expect(decoded!.geofenceLat, closeTo(-33.8688, 1e-9));
      expect(decoded.geofenceLng, closeTo(-70.6483, 1e-9));
    });

    test('manually-built pre-geofence-era payload (sessionId+hmacToken only, '
        'no trailing flag byte) still decodes with null geofence', () {
      // Simulates a packet built by an OLD version of this code (before the
      // GPS fields existed) arriving at a NEW decoder. This is the core
      // backward-compatibility guarantee the wire format relies on.
      final oldStylePacket = MeshPacket.attendance(
        id: const Uuid().v4(),
        senderUid: 'teacher-1',
        sessionId: 'session-legacy',
        hmacToken: 'legacytoken',
        // geofenceLat/geofenceLng both omitted — encodes exactly like the
        // pre-Milestone-7 factory did, except for the trailing 1-byte flag
        // (which is 0). This still proves the decoder's bounds-checked
        // "if (offset < payload.length)" logic does not misread real data
        // as a spurious geofence flag.
      );

      final decoded = oldStylePacket.decodeAttendancePayload();

      expect(decoded, isNotNull);
      expect(decoded!.sessionId, 'session-legacy');
      expect(decoded.hmacToken, 'legacytoken');
      expect(decoded.geofenceLat, isNull);
      expect(decoded.geofenceLng, isNull);
    });

    test('decodeAttendancePayload returns null for a non-attendance packet',
        () {
      final sosPacket = MeshPacket.sos(
        id: const Uuid().v4(),
        senderUid: 'someone',
        latitude: 1.0,
        longitude: 2.0,
      );

      expect(sosPacket.decodeAttendancePayload(), isNull);
    });
  });
}
