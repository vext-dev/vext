import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

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

  // FCM token refresh subscription — kept alive for the duration of the session.
  StreamSubscription<String>? _fcmTokenRefreshSub;

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

        // Save/refresh the FCM token every time a user session is active.
        // Covers both fresh sign-in and app restarts with a persisted session.
        // Fire-and-forget: FCM failure must never block the auth state stream.
        saveFcmToken(firebaseUser.uid).ignore();

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
  /// Returns true if [email] belongs to an allowed institution domain.
  /// Only @bmsce.ac.in addresses are permitted in this deployment.
  static bool isAllowedDomain(String email) {
    return email.trim().toLowerCase().endsWith('@bmsce.ac.in');
  }

  Future<VextUser> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    // ── Domain restriction ─────────────────────────────────────────────────
    // Only BMSCE institutional email addresses are allowed.
    if (!isAllowedDomain(email)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Only @bmsce.ac.in email addresses are allowed.',
      );
    }

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
    // ── Domain restriction ─────────────────────────────────────────────────
    if (!isAllowedDomain(email)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Only @bmsce.ac.in email addresses are allowed.',
      );
    }

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
  ///
  /// Uses set(merge:true) instead of update():
  ///   - update() throws NOT_FOUND if the user doc was never written (network
  ///     failure during signup). set(merge:true) creates or updates safely.
  ///
  /// Awaits waitForPendingWrites() before returning:
  ///   - Firestore security rules (callerRole()) ALWAYS evaluate against SERVER
  ///     data, not local cache. If this method returned before the write reached
  ///     the server, the caller could immediately try a role-guarded operation
  ///     (e.g. creating a session as teacher) and get permission-denied because
  ///     the server still has the old role value.
  ///   - 10-second timeout: if offline, we proceed anyway; the write will sync
  ///     when connectivity is restored.
  Future<void> updateRole(String uid, String role) async {
    await _firestore
        .collection(AppConstants.fsUsers)
        .doc(uid)
        .set({'role': role}, SetOptions(merge: true));

    // Ensure the role reaches the server before returning.
    await _firestore.waitForPendingWrites().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        // Offline — proceed. Role-guarded operations may fail until sync completes,
        // but that's correct behaviour (security rules are server-side).
        debugPrint('[Auth] waitForPendingWrites timed out — device may be offline');
      },
    );
  }

  // ── FCM Token ─────────────────────────────────────────────────────────────

  /// Fetch the current FCM registration token and save it to Firestore.
  ///
  /// The handleSOSAlert Cloud Function queries users/{uid}.fcmToken to find
  /// security-role devices to push to. Without this field populated, no SOS
  /// push notification ever fires.
  ///
  /// Also subscribes to FirebaseMessaging.onTokenRefresh so the field stays
  /// current if FCM rotates the token (happens after app reinstall, token
  /// expiry, or FCM maintenance).
  ///
  /// This method is fire-and-forget from the call sites — it must NEVER throw
  /// or propagate errors, since FCM failure must not block auth or BLE startup.
  Future<void> saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return; // FCM not available (emulator, permission denied)

      await _firestore
          .collection(AppConstants.fsUsers)
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));

      // Cancel any previous refresh listener before setting up a new one.
      // This prevents duplicate listeners if saveFcmToken is called multiple
      // times (e.g. app restart with persisted session).
      _fcmTokenRefreshSub?.cancel();
      _fcmTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) {
          _firestore
              .collection(AppConstants.fsUsers)
              .doc(uid)
              .set({'fcmToken': newToken}, SetOptions(merge: true))
              .ignore();
        },
        onError: (e) {
          debugPrint('[FCM] onTokenRefresh error: $e');
        },
      );
    } catch (e) {
      // Best-effort — FCM unavailability must never block the app.
      debugPrint('[FCM] saveFcmToken failed for uid=$uid: $e');
    }
  }

  // ── Sign Out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    // Cancel FCM token refresh listener and delete the token from FCM.
    // Deleting the token prevents push notifications from arriving after
    // sign-out (the Cloud Function would otherwise still find this device's
    // token in Firestore and push to it).
    _fcmTokenRefreshSub?.cancel();
    _fcmTokenRefreshSub = null;
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        // Remove fcmToken from Firestore so the Cloud Function doesn't push
        // to a logged-out device.
        await _firestore
            .collection(AppConstants.fsUsers)
            .doc(uid)
            .set({'fcmToken': FieldValue.delete()}, SetOptions(merge: true));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[FCM] signOut token cleanup failed: $e');
    }

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
