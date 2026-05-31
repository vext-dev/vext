import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_constants.dart';

/// Represents an authenticated VEXT user with their role.
class VextUser {
  final String uid;
  final String email;
  final String displayName;
  // '' (empty) means the user has not yet selected a role.
  // The router uses this to redirect to RoleSelectionScreen.
  final String role; // '' | student | teacher | security
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
      // Default to '' (no role) — empty string means "not yet selected".
      // The router redirects to RoleSelectionScreen when role is empty.
      role: data['role'] as String? ?? '',
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
  ///
  /// Uses [asyncExpand] + Firestore [snapshots()] instead of a one-shot [get()].
  /// This gives us two critical properties:
  ///
  /// 1. Race-condition safety: Firebase Auth fires [authStateChanges] the moment
  ///    a user is created — before the Firestore document is written. With [get()]
  ///    the read races the write and returns null, making the app think the user
  ///    logged out. With [snapshots()], we emit a stub immediately and then the
  ///    real user as soon as the document is committed to the local Firestore cache.
  ///
  /// 2. Reactive role updates: When [updateRole()] writes to Firestore, the
  ///    [snapshots()] listener fires automatically. [authStateProvider] updates,
  ///    the router re-evaluates, and navigation happens without any explicit
  ///    [context.go()] call in [RoleSelectionScreen].
  ///
  /// [asyncExpand] starts a new inner Firestore snapshot stream for each Firebase
  /// Auth event. For this app (login/logout only; no token-refresh events that
  /// fire new authStateChanges), this produces exactly one inner stream per session.
  Stream<VextUser?> get authStateChanges {
    return _auth.authStateChanges().asyncExpand((firebaseUser) {
      // Logged out — emit null once and complete the inner stream.
      if (firebaseUser == null) return Stream.value(null);

      // Logged in — open a real-time Firestore listener on the user document.
      // This stream emits on every document change (role update, key upload, etc.).
      return _firestore
          .collection(AppConstants.fsUsers)
          .doc(firebaseUser.uid)
          .snapshots()
          .map((doc) {
            if (!doc.exists || doc.data() == null) {
              // Document not yet written (signup race) or was deleted.
              // Return a minimal stub so [authStateProvider] stays non-null
              // and the router knows we ARE logged in — just without a role yet.
              // The router will redirect to RoleSelectionScreen.
              return VextUser(
                uid: firebaseUser.uid,
                email: firebaseUser.email ?? '',
                displayName: firebaseUser.displayName ?? '',
                role: '',        // empty role → RoleSelectionScreen
                institutionId: '',
              );
            }
            return VextUser.fromMap(firebaseUser.uid, doc.data()!);
          });
    });
  }

  /// Current user synchronously (null if not signed in).
  User? get currentFirebaseUser => _auth.currentUser;

  // ── Sign Up ────────────────────────────────────────────────────────────────

  /// Creates account, stores profile in Firestore.
  ///
  /// The Firestore document is written with [role: ''] (empty string) so that
  /// the router correctly routes this user to [RoleSelectionScreen]. Role is
  /// set by a subsequent call to [updateRole()] from [RoleSelectionScreen].
  Future<VextUser> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user!;

    // Update display name in Firebase Auth.
    await user.updateDisplayName(name);

    // Create user document in Firestore with empty role.
    // Role is assigned in RoleSelectionScreen → updateRole().
    final vextUser = VextUser(
      uid: user.uid,
      email: email,
      displayName: name,
      role: '',            // NO default role — user must select in RoleSelectionScreen
      institutionId: 'default',
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

    final firebaseUser = credential.user!;
    var vextUser = await _fetchVextUser(firebaseUser.uid);

    if (vextUser == null) {
      // Self-healing: Firestore document was never written (network failure
      // during signup, or partially-created account). Reconstruct from
      // Firebase Auth data so the user is not permanently locked out.
      // They will be routed to RoleSelectionScreen to complete their profile.
      vextUser = VextUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? email,
        displayName: firebaseUser.displayName ?? '',
        role: '',
        institutionId: 'default',
      );
      await _firestore
          .collection(AppConstants.fsUsers)
          .doc(firebaseUser.uid)
          .set(vextUser.toMap());
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
