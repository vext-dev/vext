import 'dart:async';

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

  // Cached stream and its active Firestore subscription — lazily initialised.
  // Using a single cached stream ensures all watchers (authStateProvider,
  // _RouterNotifier) share the same underlying subscription chain.
  Stream<VextUser?>? _authStateChangesCache;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _firestoreSub;

  /// Emits [VextUser] when logged in, null when logged out.
  ///
  /// Implements SWITCHMAP semantics over Firebase Auth + Firestore snapshots:
  ///   • Reacts to role updates via Firestore [snapshots()] — reactive role routing.
  ///   • Cancels the Firestore subscription IMMEDIATELY when Firebase Auth fires
  ///     a new event (login/logout). This is the critical difference from
  ///     [asyncExpand], which PAUSES the outer stream while the inner stream is
  ///     active. Because Firestore [snapshots()] never completes (infinite stream),
  ///     [asyncExpand] would permanently pause the Firebase Auth outer stream after
  ///     first login — causing [signOut()] events to be DROPPED by the broadcast
  ///     stream and sign-out to appear permanently stuck (spinner never stops,
  ///     router never redirects to /login).
  ///
  /// This getter is lazy-initialised and returns the same stream on every call,
  /// since [authServiceProvider] is a singleton and [authStateProvider] subscribes
  /// exactly once for the app lifetime.
  Stream<VextUser?> get authStateChanges {
    return _authStateChangesCache ??= _buildAuthStateChanges();
  }

  Stream<VextUser?> _buildAuthStateChanges() {
    // Broadcast controller: multiple Riverpod providers can subscribe
    // (_RouterNotifier via authStateProvider, etc.) without conflict.
    final controller = StreamController<VextUser?>.broadcast();

    // Subscribe to Firebase Auth. This subscription lives for the app lifetime.
    _auth.authStateChanges().listen(
      (firebaseUser) {
        // ── SWITCHMAP: cancel the old Firestore listener immediately ──────────
        // This is what asyncExpand DOES NOT do. asyncExpand waits for the inner
        // stream to complete before processing the next outer event. Firestore
        // snapshots() NEVER complete, so asyncExpand would block here forever and
        // the signOut null event would be silently dropped (broadcast streams drop
        // events to paused subscribers). By cancelling explicitly, we guarantee the
        // signOut event propagates immediately.
        _firestoreSub?.cancel();
        _firestoreSub = null;

        if (firebaseUser == null) {
          // User signed out — emit null so the router redirects to /login.
          controller.add(null);
          return;
        }

        // User signed in — open a real-time Firestore listener on the user document.
        // Emits on every document change (role update, key upload, etc.) so the
        // router can reactively redirect after role selection — no explicit
        // context.go() call needed anywhere.
        _firestoreSub = _firestore
            .collection(AppConstants.fsUsers)
            .doc(firebaseUser.uid)
            .snapshots()
            .listen(
              (doc) {
                if (!doc.exists || doc.data() == null) {
                  // Document not yet written (signup race) or deleted.
                  // Emit a stub: router sees isLoggedIn=true, hasRole=false
                  // → redirects to RoleSelectionScreen.
                  controller.add(VextUser(
                    uid: firebaseUser.uid,
                    email: firebaseUser.email ?? '',
                    displayName: firebaseUser.displayName ?? '',
                    role: '',        // empty role → RoleSelectionScreen
                    institutionId: '',
                  ));
                } else {
                  controller.add(VextUser.fromMap(firebaseUser.uid, doc.data()!));
                }
              },
              onError: controller.addError,
            );
      },
      onError: controller.addError,
      onDone: () {
        // Firebase Auth stream closed (only happens if the app is torn down).
        _firestoreSub?.cancel();
        controller.close();
      },
    );

    return controller.stream;
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
    // Cancel the Firestore snapshot subscription eagerly before Firebase Auth
    // fires its null event. This is belt-and-suspenders — the _buildAuthStateChanges
    // listener also cancels it, but doing it here guarantees no Firestore reads
    // happen after the user session ends (avoids permission-denied errors in
    // environments with Firestore security rules enabled).
    _firestoreSub?.cancel();
    _firestoreSub = null;
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
