// ── CryptoService Unit Tests ───────────────────────────────────────────────────
//
// Tests Ed25519 sign/verify, X25519 ECDH + AES-256-GCM encrypt/decrypt,
// HMAC-SHA256 window verification, fingerprint format, and EncryptedMessage
// serialisation — all without real Android Keystore I/O.
//
// flutter_secure_storage is mocked via the official setMockInitialValues({}) API,
// which wires an in-memory map to the plugin's MethodChannel. Requires the Flutter
// test binding (TestWidgetsFlutterBinding) to be initialized first.
//
// The cryptography package is pure Dart — no platform channels — so sign/encrypt
// operations run without any native code in the test environment.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vext/services/crypto_service.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Resets the in-memory secure storage and returns a freshly initialized service.
Future<CryptoService> _freshService() async {
  FlutterSecureStorage.setMockInitialValues({});
  final s = CryptoService();
  await s.initialize();
  return s;
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUp(() async {
    crypto = await _freshService();
  });

  // ── Fingerprint ──────────────────────────────────────────────────────────────

  group('Fingerprint', () {
    test('is 16 lowercase hex characters (8 bytes of SHA-256)', () {
      final fp = crypto.fingerprint;
      expect(fp.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(fp), isTrue);
    });

    test('is stable across multiple accesses on the same instance', () {
      expect(crypto.fingerprint, crypto.fingerprint);
    });

    test('is stable when re-initialized from the same stored keys', () async {
      final fp1 = crypto.fingerprint;
      // Re-init WITHOUT clearing storage → same keypair loaded.
      final crypto2 = CryptoService();
      await crypto2.initialize();
      expect(crypto2.fingerprint, fp1,
          reason: 'fingerprint must be deterministic from the stored keypair');
    });

    test('differs between instances with different keypairs', () async {
      final fp1 = crypto.fingerprint;
      final crypto2 = await _freshService(); // fresh store → new keypair
      expect(crypto2.fingerprint, isNot(equals(fp1)));
    });
  });

  // ── Ed25519 sign / verify ─────────────────────────────────────────────────────

  group('Ed25519 sign / verify', () {
    test('sign → verify roundtrip returns true', () async {
      final data = [1, 2, 3, 4, 5, 6, 7, 8];
      final sig = await crypto.signData(data);
      final pubKey = await crypto.getEd25519PublicKeyBytes();

      expect(await crypto.verifySignature(data, sig, pubKey), isTrue);
    });

    test('signature is 64 bytes', () async {
      final sig = await crypto.signData([0x42]);
      expect(sig.length, 64);
    });

    test('verify fails when data is tampered', () async {
      final data = [1, 2, 3, 4];
      final sig = await crypto.signData(data);
      final pubKey = await crypto.getEd25519PublicKeyBytes();

      expect(
        await crypto.verifySignature([9, 9, 9, 9], sig, pubKey),
        isFalse,
      );
    });

    test('verify fails when signature is tampered', () async {
      final data = [1, 2, 3, 4];
      final sigBytes = await crypto.signData(data);
      final pubKey = await crypto.getEd25519PublicKeyBytes();

      final tampered = Uint8List.fromList(sigBytes);
      tampered[32] ^= 0xFF; // flip a bit in the middle

      expect(await crypto.verifySignature(data, tampered, pubKey), isFalse);
    });

    test("verify fails with a different node's public key", () async {
      final data = [1, 2, 3, 4];
      final sig = await crypto.signData(data);

      final other = await _freshService();
      final wrongPubKey = await other.getEd25519PublicKeyBytes();

      expect(await crypto.verifySignature(data, sig, wrongPubKey), isFalse);
    });
  });

  // ── AES-256-GCM encrypt / decrypt (via X25519 ECDH) ─────────────────────────

  group('AES-256-GCM encrypt / decrypt', () {
    test('encrypt → decrypt roundtrip recovers plaintext', () async {
      final recipient = await _freshService();
      final recipientPubKey = await recipient.getX25519PublicKeyBytes();
      final senderPubKey    = await crypto.getX25519PublicKeyBytes();

      const plaintext = 'Hello VEXT mesh! 🔐';
      final encrypted = await crypto.encryptMessage(plaintext, recipientPubKey);
      final decrypted = await recipient.decryptMessage(encrypted, senderPubKey);

      expect(decrypted, plaintext);
    });

    test('decrypt with wrong sender key throws (GCM auth tag fails)', () async {
      final recipient = await _freshService();
      final recipientPubKey = await recipient.getX25519PublicKeyBytes();

      final encrypted =
          await crypto.encryptMessage('secret data', recipientPubKey);

      final imposter     = await _freshService();
      final wrongPubKey  = await imposter.getX25519PublicKeyBytes();

      await expectLater(
        () => recipient.decryptMessage(encrypted, wrongPubKey),
        throwsA(anything),
        reason: 'GCM authentication must reject a wrong shared secret',
      );
    });

    test('encrypting the same plaintext twice produces different nonces', () async {
      final recipient    = await _freshService();
      final recipientPubKey = await recipient.getX25519PublicKeyBytes();

      final e1 = await crypto.encryptMessage('same text', recipientPubKey);
      final e2 = await crypto.encryptMessage('same text', recipientPubKey);

      expect(e1.nonce, isNot(equals(e2.nonce)),
          reason: 'each AES-GCM encryption must use a fresh random nonce');
    });

    test('empty string roundtrips correctly', () async {
      final recipient    = await _freshService();
      final recipientPubKey = await recipient.getX25519PublicKeyBytes();
      final senderPubKey    = await crypto.getX25519PublicKeyBytes();

      final encrypted = await crypto.encryptMessage('', recipientPubKey);
      final decrypted = await recipient.decryptMessage(encrypted, senderPubKey);
      expect(decrypted, '');
    });
  });

  // ── HMAC-SHA256 token — Lane A attendance ────────────────────────────────────

  group('HMAC token', () {
    test('token generated and verified in the same 90-second window', () async {
      final token = await crypto.generateHmacToken('session-1', 'cs101');
      expect(await crypto.verifyHmacToken('session-1', 'cs101', token), isTrue);
    });

    test('token is 64 lowercase hex characters (32-byte HMAC-SHA256)', () async {
      final token = await crypto.generateHmacToken('session-x', 'eng201');
      expect(token.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(token), isTrue);
    });

    test('wrong token returns false', () async {
      final ok = await crypto.verifyHmacToken(
        'session-1',
        'cs101',
        // 64 hex chars, but not a valid HMAC for this session
        'badc0ffee0ddf00dbadc0ffee0ddf00dbadc0ffee0ddf00dbadc0ffee0ddf00d',
      );
      expect(ok, isFalse);
    });

    test('token for a different courseId does not verify', () async {
      final token = await crypto.generateHmacToken('session-1', 'cs101');
      expect(
        await crypto.verifyHmacToken('session-1', 'cs999', token),
        isFalse,
      );
    });

    test('token for a different sessionId does not verify', () async {
      final token = await crypto.generateHmacToken('session-1', 'cs101');
      expect(
        await crypto.verifyHmacToken('session-999', 'cs101', token),
        isFalse,
      );
    });

    test('token from a different CryptoService (different key) does not verify',
        () async {
      final other = await _freshService(); // different Ed25519 key → different HMAC key
      final token = await other.generateHmacToken('session-1', 'cs101');
      expect(
        await crypto.verifyHmacToken('session-1', 'cs101', token),
        isFalse,
      );
    });
  });

  // ── EncryptedMessage serialisation ───────────────────────────────────────────

  group('EncryptedMessage toBytes / fromBytes', () {
    test('roundtrip preserves nonce, mac, and ciphertext', () {
      final original = EncryptedMessage(
        ciphertext: Uint8List.fromList(List.generate(32, (i) => i)),
        nonce:      Uint8List.fromList(List.generate(12, (i) => i + 100)),
        mac:        Uint8List.fromList(List.generate(16, (i) => i + 200)),
      );

      final restored = EncryptedMessage.fromBytes(original.toBytes());

      expect(restored, isNotNull);
      expect(restored!.nonce,      original.nonce);
      expect(restored.mac,         original.mac);
      expect(restored.ciphertext,  original.ciphertext);
    });

    test('byte layout is nonce(12) + mac(16) + ciphertext', () {
      final nonce      = Uint8List.fromList(List.filled(12, 0xAA));
      final mac        = Uint8List.fromList(List.filled(16, 0xBB));
      final ciphertext = Uint8List.fromList(List.filled(8,  0xCC));

      final bytes = EncryptedMessage(
        nonce: nonce, mac: mac, ciphertext: ciphertext,
      ).toBytes();

      expect(bytes.length, 36);
      expect(bytes.sublist(0, 12),  everyElement(0xAA));
      expect(bytes.sublist(12, 28), everyElement(0xBB));
      expect(bytes.sublist(28),     everyElement(0xCC));
    });

    test('fromBytes returns null for input shorter than 28 bytes', () {
      expect(EncryptedMessage.fromBytes(Uint8List(27)), isNull);
      expect(EncryptedMessage.fromBytes(Uint8List(0)),  isNull);
    });

    test('fromBytes accepts exactly 28 bytes (empty ciphertext)', () {
      final bytes = Uint8List(28); // nonce(12) + mac(16) + ciphertext(0)
      final msg = EncryptedMessage.fromBytes(bytes);
      expect(msg, isNotNull);
      expect(msg!.ciphertext.length, 0);
    });
  });
}
