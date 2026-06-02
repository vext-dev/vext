// ── CryptoService — VEXT Cryptographic Key Management & Operations ─────────────
//
// All cryptographic operations for VEXT VigilantMesh go through this service.
// Private keys are stored in Android Keystore (via flutter_secure_storage).
// Public keys are uploaded to Firestore in Milestone 7.
//
// Key material (per device, generated once on first launch):
//   X25519 keypair  — Diffie-Hellman key exchange for Lane B message encryption
//   Ed25519 keypair — Digital signature for Lane A attendance proofs + Lane C SOS
//
// Operations:
//   generateHmacToken(sessionId, courseId)  — Lane A teacher token (90-second window)
//   verifyHmacToken(sessionId, courseId, token, window) — Lane A student verification
//   signData(bytes)                          — Ed25519 sign for attendance/SOS proofs
//   verifySignature(bytes, sig, publicKey)   — Verify an Ed25519 signature
//   encryptMessage(plaintext, recipientPk)  — AES-256-GCM for Lane B messages
//   decryptMessage(ciphertext, nonce, mac, senderPk) — Decrypt a Lane B message
//   getPublicKeyFingerprint()               — SHA-256[:8] hex node identifier
//
// Package: cryptography ^2.7.0 (NOT pointycastle — API too complex for this project)
// Storage: flutter_secure_storage ^9.x with Android EncryptedSharedPreferences
//
// Academic references:
//   X25519 + AES-256-GCM: used by Signal, WireGuard, TLS 1.3
//   Ed25519: RFC 8032, used by OpenSSH, Ethereum
//   HMAC-SHA256: NIST FIPS 198-1
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/app_constants.dart';

// ── EncryptedMessage — result of encryptMessage() ────────────────────────────

/// Container for AES-256-GCM encrypted output.
/// All three fields are required to decrypt.
class EncryptedMessage {
  const EncryptedMessage({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  final Uint8List ciphertext; // AES-256-GCM ciphertext
  final Uint8List nonce;      // 12-byte random nonce (IV)
  final Uint8List mac;        // 16-byte GCM authentication tag

  /// Serialise to a flat byte array: nonce(12) + mac(16) + ciphertext(N).
  Uint8List toBytes() {
    final out = Uint8List(12 + 16 + ciphertext.length);
    out.setRange(0, 12, nonce);
    out.setRange(12, 28, mac);
    out.setRange(28, out.length, ciphertext);
    return out;
  }

  /// Deserialise from [toBytes()] output. Returns null if too short.
  static EncryptedMessage? fromBytes(Uint8List bytes) {
    if (bytes.length < 28) return null;
    return EncryptedMessage(
      nonce:      bytes.sublist(0, 12),
      mac:        bytes.sublist(12, 28),
      ciphertext: bytes.sublist(28),
    );
  }
}

// ── CryptoService ─────────────────────────────────────────────────────────────

class CryptoService {
  // ── Secure storage ────────────────────────────────────────────────────────

  static const _storage = FlutterSecureStorage(
    // encryptedSharedPreferences = keys stored in Android Keystore-backed storage.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Secure-storage key names — private key bytes stored as base64 strings.
  static const _keyX25519Private = 'vext_x25519_private';
  static const _keyX25519Public  = 'vext_x25519_public';
  static const _keyEd25519Private = 'vext_ed25519_private';
  static const _keyEd25519Public  = 'vext_ed25519_public';

  // ── Crypto algorithms (from `cryptography` package) ──────────────────────

  static final _x25519   = X25519();
  static final _ed25519  = Ed25519();
  static final _aesgcm   = AesGcm.with256bits();
  static final _hmacSha256 = Hmac.sha256();
  static final _sha256   = Sha256();

  // ── In-memory keypair cache (loaded once on initialize()) ────────────────

  SimpleKeyPair? _x25519KeyPair;
  SimpleKeyPair? _ed25519KeyPair;
  String? _fingerprint;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Load existing keypairs from secure storage, or generate them if absent.
  /// Must be called before any other method.
  Future<void> initialize() async {
    _x25519KeyPair  = await _loadOrGenerateX25519();
    _ed25519KeyPair = await _loadOrGenerateEd25519();
    _fingerprint    = await _computeFingerprint();
  }

  // ── Public key fingerprint ────────────────────────────────────────────────

  /// 16 hex chars (8 bytes) identifying this node in the mesh.
  /// Derived as SHA-256(X25519 public key bytes)[:8].
  ///
  /// Stable across app restarts. Stored in MeshPacket.senderUid and
  /// uploaded to Firestore public_keys/{uid} in Milestone 7.
  String get fingerprint {
    // Use a runtime null check (not assert — asserts are stripped in release builds).
    if (_fingerprint == null) {
      throw StateError('CryptoService.initialize() was not called before accessing fingerprint');
    }
    return _fingerprint!;
  }

  // ── X25519 public key ─────────────────────────────────────────────────────

  /// Returns this node's X25519 public key bytes.
  /// Upload to Firestore so peers can derive a shared secret for Lane B.
  Future<Uint8List> getX25519PublicKeyBytes() async {
    final kp = _assertX25519();
    final pk = await kp.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  // ── Ed25519 public key ────────────────────────────────────────────────────

  /// Returns this node's Ed25519 public key bytes.
  Future<Uint8List> getEd25519PublicKeyBytes() async {
    final kp = _assertEd25519();
    final pk = await kp.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  // ── HMAC-SHA256 — Lane A teacher tokens ──────────────────────────────────

  /// Generate an HMAC-SHA256 token for an attendance session.
  ///
  /// Token binds: sessionId + courseId + current 90-second window index.
  /// The teacher broadcasts this token in the BLE advertisement payload.
  /// Students include it in their attendance proof — the teacher verifies
  /// it was generated within the valid time window.
  ///
  /// Returns hex-encoded 32-byte MAC.
  Future<String> generateHmacToken(String sessionId, String courseId) async {
    final key = await _getHmacKey();
    final windowIndex = _currentWindowIndex();
    final data = utf8.encode('$sessionId:$courseId:$windowIndex');
    final mac = await _hmacSha256.calculateMac(data, secretKey: key);
    return _bytesToHex(mac.bytes);
  }

  /// Verify a token against the current AND previous time window.
  ///
  /// Accepting the previous window (max 90 s old) allows for:
  ///   • Clock drift between teacher and student devices.
  ///   • Network/BLE propagation delay.
  Future<bool> verifyHmacToken(
    String sessionId,
    String courseId,
    String tokenHex,
  ) async {
    final key = await _getHmacKey();
    final currentWindow = _currentWindowIndex();

    for (final window in [currentWindow, currentWindow - 1]) {
      final data = utf8.encode('$sessionId:$courseId:$window');
      final expected = await _hmacSha256.calculateMac(data, secretKey: key);
      if (_bytesToHex(expected.bytes) == tokenHex) return true;
    }
    return false;
  }

  // ── Ed25519 — signing (Lane A proofs + Lane C SOS) ───────────────────────

  /// Sign [data] bytes with this node's Ed25519 private key.
  /// Returns the 64-byte signature as a [Uint8List].
  Future<Uint8List> signData(List<int> data) async {
    final kp = _assertEd25519();
    final signature = await _ed25519.sign(data, keyPair: kp);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify an Ed25519 [signatureBytes] over [data] using [publicKeyBytes].
  /// Returns true if the signature is valid.
  Future<bool> verifySignature(
    List<int> data,
    List<int> signatureBytes,
    List<int> publicKeyBytes,
  ) async {
    try {
      final publicKey =
          SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(
        signatureBytes,
        publicKey: publicKey,
      );
      return await _ed25519.verify(data, signature: signature);
    } catch (_) {
      return false;
    }
  }

  // ── AES-256-GCM — Lane B message encryption ──────────────────────────────

  /// Encrypt [plaintext] for [recipientX25519PublicKeyBytes].
  ///
  /// Uses X25519 ECDH to derive a shared secret, then AES-256-GCM to encrypt.
  /// The nonce is randomly generated per message — never reuse a nonce.
  Future<EncryptedMessage> encryptMessage(
    String plaintext,
    List<int> recipientX25519PublicKeyBytes,
  ) async {
    final sharedSecret = await _deriveSharedSecret(recipientX25519PublicKeyBytes);

    final secretBox = await _aesgcm.encrypt(
      utf8.encode(plaintext),
      secretKey: sharedSecret,
    );

    return EncryptedMessage(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce:      Uint8List.fromList(secretBox.nonce),
      mac:        Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Decrypt a message from [senderX25519PublicKeyBytes].
  ///
  /// Derives the same shared secret (ECDH is symmetric) and decrypts with
  /// AES-256-GCM. Returns the plaintext or throws on authentication failure.
  Future<String> decryptMessage(
    EncryptedMessage encrypted,
    List<int> senderX25519PublicKeyBytes,
  ) async {
    final sharedSecret = await _deriveSharedSecret(senderX25519PublicKeyBytes);

    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac:   Mac(encrypted.mac),
    );

    final plainBytes = await _aesgcm.decrypt(secretBox, secretKey: sharedSecret);
    return utf8.decode(plainBytes);
  }

  // ── Key serialisation helpers ─────────────────────────────────────────────

  /// Convert an X25519 public key bytes list to a [SimplePublicKey].
  SimplePublicKey x25519PublicKeyFromBytes(List<int> bytes) =>
      SimplePublicKey(bytes, type: KeyPairType.x25519);

  /// Convert an Ed25519 public key bytes list to a [SimplePublicKey].
  SimplePublicKey ed25519PublicKeyFromBytes(List<int> bytes) =>
      SimplePublicKey(bytes, type: KeyPairType.ed25519);

  // ── Private — key loading / generation ───────────────────────────────────

  Future<SimpleKeyPair> _loadOrGenerateX25519() async {
    final privB64 = await _storage.read(key: _keyX25519Private);
    final pubB64  = await _storage.read(key: _keyX25519Public);

    if (privB64 != null && pubB64 != null) {
      return SimpleKeyPairData(
        base64Decode(privB64),
        publicKey: SimplePublicKey(
          base64Decode(pubB64),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    }

    // Generate fresh keypair and persist it.
    final kp  = await _x25519.newKeyPair();
    final pk  = await kp.extractPublicKey();
    final prv = await kp.extractPrivateKeyBytes();

    await _storage.write(key: _keyX25519Private, value: base64Encode(prv));
    await _storage.write(key: _keyX25519Public,  value: base64Encode(pk.bytes));

    return kp;
  }

  Future<SimpleKeyPair> _loadOrGenerateEd25519() async {
    final privB64 = await _storage.read(key: _keyEd25519Private);
    final pubB64  = await _storage.read(key: _keyEd25519Public);

    if (privB64 != null && pubB64 != null) {
      return SimpleKeyPairData(
        base64Decode(privB64),
        publicKey: SimplePublicKey(
          base64Decode(pubB64),
          type: KeyPairType.ed25519,
        ),
        type: KeyPairType.ed25519,
      );
    }

    final kp  = await _ed25519.newKeyPair();
    final pk  = await kp.extractPublicKey();
    final prv = await kp.extractPrivateKeyBytes();

    await _storage.write(key: _keyEd25519Private, value: base64Encode(prv));
    await _storage.write(key: _keyEd25519Public,  value: base64Encode(pk.bytes));

    return kp;
  }

  Future<String> _computeFingerprint() async {
    final pubBytes = await getX25519PublicKeyBytes();
    final hash = await _sha256.hash(pubBytes);
    return _bytesToHex(hash.bytes.take(8).toList());
  }

  // ── Private — HMAC key derivation ────────────────────────────────────────

  /// HMAC key: first 32 bytes of the Ed25519 private key.
  /// Ties the HMAC to teacher identity — students cannot forge it.
  Future<SecretKey> _getHmacKey() async {
    final kp  = _assertEd25519();
    final prv = await kp.extractPrivateKeyBytes();
    return SecretKey(prv.take(32).toList());
  }

  // ── Private — ECDH shared secret ─────────────────────────────────────────

  Future<SecretKey> _deriveSharedSecret(List<int> peerPublicKeyBytes) async {
    final kp = _assertX25519();
    final peerPk = SimplePublicKey(peerPublicKeyBytes, type: KeyPairType.x25519);
    return _x25519.sharedSecretKey(keyPair: kp, remotePublicKey: peerPk);
  }

  // ── Private — HMAC window ─────────────────────────────────────────────────

  /// Window index changes every 90 seconds. Two consecutive windows are
  /// accepted during verification to handle clock drift.
  int _currentWindowIndex() =>
      DateTime.now().millisecondsSinceEpoch ~/ (AppConstants.hmacWindowSeconds * 1000);

  // ── Private — helpers ─────────────────────────────────────────────────────

  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  SimpleKeyPair _assertX25519() {
    if (_x25519KeyPair == null) {
      throw StateError('CryptoService.initialize() was not called — X25519 keypair not loaded');
    }
    return _x25519KeyPair!;
  }

  SimpleKeyPair _assertEd25519() {
    if (_ed25519KeyPair == null) {
      throw StateError('CryptoService.initialize() was not called — Ed25519 keypair not loaded');
    }
    return _ed25519KeyPair!;
  }
}
