// ── PublicKeyDirectoryService — Firestore X25519 public-key directory ─────────
//
// Milestone 7 (Lane B 1:1 encrypted DM). Each device uploads its own
// X25519 public key (the full key bytes, not just the fingerprint) so peers
// can derive a shared ECDH secret with CryptoService before encrypting a
// direct message to them.
//
// This is intentionally a SEPARATE collection from users/{uid} rather than
// a new field there:
//   • users/{uid}.public_key already exists and holds only the 16-hex-char
//     SHA-256 fingerprint (a debug/display identifier) — repurposing it to
//     hold full key bytes would be a breaking change to existing reads.
//   • CryptoService's own fingerprint doc comment already documented the
//     original intent: "uploaded to Firestore public_keys/{uid} in
//     Milestone 7" — this collection name and shape was anticipated by the
//     original design, not invented here.
//
// Firestore document shape — public_keys/{uid}:
//   { publicKeyBytes: base64 string, updatedAt: server timestamp }
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_constants.dart';

class PublicKeyDirectoryService {
  PublicKeyDirectoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// In-memory cache so repeated DMs to the same peer within one app session
  /// don't re-fetch from Firestore every time. Cleared on app restart —
  /// acceptable since key rotation is rare and a restart naturally refreshes.
  final Map<String, Uint8List> _cache = {};

  /// Upload this device's own X25519 public key so peers can find it.
  /// Safe to call on every app start / sign-in — it's an idempotent merge-set.
  /// Call site: SocialService.initialize(), fire-and-forget (failure here
  /// just means peers can't yet DM this device until the next successful
  /// attempt — not fatal to any other lane).
  Future<void> uploadOwnPublicKey({
    required String uid,
    required List<int> publicKeyBytes,
  }) async {
    await _firestore
        .collection(AppConstants.fsPublicKeys)
        .doc(uid)
        .set({
      'publicKeyBytes': base64Encode(publicKeyBytes),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetch [peerUid]'s X25519 public key bytes, or null if they haven't
  /// uploaded one yet (e.g. never opened the app since this feature shipped).
  /// Callers (SocialService.sendDirectMessage) must surface this as
  /// "can't message this user yet" rather than silently failing.
  Future<Uint8List?> getPublicKey(String peerUid) async {
    final cached = _cache[peerUid];
    if (cached != null) return cached;

    final doc = await _firestore
        .collection(AppConstants.fsPublicKeys)
        .doc(peerUid)
        .get();
    final raw = doc.data()?['publicKeyBytes'] as String?;
    if (raw == null) return null;

    final bytes = Uint8List.fromList(base64Decode(raw));
    _cache[peerUid] = bytes;
    return bytes;
  }
}
