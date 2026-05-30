import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_constants.dart';

/// Represents an authenticated VEXT user with their role.
class VextUser {
  final String uid;
  final String email;
  final String displayName;
  final String role; // student | teacher | security
  final String institutionId;
  final String publicKeyFingerprint; // set after crypto init

  const VextUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.institutionId,
    this.publicKeyFingerprint = '',
  });

  factory VextUser.fromMap(String uid, Map<String, dynamic> data) {
    return VextUser(
      uid: uid,
      email: data['email'] as String? ?? '',
      displayName: data['name'] as String? ?? '',
      role: data['role'] as String? ?? AppConstants.roleStudent,
      institutionId: data['institution_id'] as String? ?? '',
      publicKeyFingerprint: data['public_key'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'name': displayName,
        'role': role,
        'institution_id': institutionId,
        'public_key': publicKeyFingerprint,
        'created_at': FieldValue.serverTimestamp(),
      };

  VextUser copyWith({String? role, String? publicKeyFingerprint}) {
    return VextUser(
      uid: uid,
      email: email,
      displayName: displayName,
      role: role ?? this.role,
      institutionId: institutionId,
      publicKeyFingerprint:
          publicKeyFingerprint ?? this.publicKeyFingerprint,
    );
  }
}

/// Handles all Firebase Authentication and user profile operations.
/// Single responsibility: auth state only. No BLE, no crypto here.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  // ── Auth State Stream ──────────────────────────────────────────────────────

  /// Emits [VextUser] when logged in, null when logged out.
  /// Used by the router to redirect to login/home.
  Stream<VextUser?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      return _fetchVextUser(firebaseUser.uid);
    });
  }

  /// Current user synchronously (null if not signed in).
  User? get currentFirebaseUser => _auth.currentUser;

  // ── Sign Up ────────────────────────────────────────────────────────────────

  /// Creates account, stores profile in Firestore.
  /// [role] must be one of AppConstants.roleStudent / roleTeacher / roleSecurity.
  Future<VextUser> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    String role = AppConstants.roleStudent,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user!;

    // Update display name in Firebase Auth
    await user.updateDisplayName(name);

    // Create user document in Firestore
    final vextUser = VextUser(
      uid: user.uid,
      email: email,
      displayName: name,
      role: role,
      institutionId: 'default', // updated after role selection if needed
    );

    await _firestore
        .collection(AppConstants.fsUsers)
        .doc(user.uid)
        .set(vextUser.toMap());

    return vextUser;
  }

  // ── Sign In ────────────────────────────────────────────────────────────────

  Future<VextUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final vextUser = await _fetchVextUser(credential.user!.uid);
    if (vextUser == null) {
      throw Exception('User profile not found. Please contact support.');
    }
    return vextUser;
  }

  // ── Update Role ────────────────────────────────────────────────────────────

  /// Called after role selection screen to persist chosen role.
  Future<void> updateRole(String uid, String role) async {
    await _firestore
        .collection(AppConstants.fsUsers)
        .doc(uid)
        .update({'role': role});
  }

  // ── Sign Out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<VextUser?> _fetchVextUser(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.fsUsers)
        .doc(uid)
        .get();

    if (!doc.exists || doc.data() == null) return null;
    return VextUser.fromMap(uid, doc.data()!);
  }
}
