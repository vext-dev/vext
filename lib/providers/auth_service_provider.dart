import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

/// Singleton provider for [AuthService].
/// All widgets that need auth operations read this.
///
/// ref.onDispose cancels the Firebase Auth and Firestore subscriptions
/// inside AuthService when the ProviderScope is disposed (test teardown,
/// app exit). In production the scope lives for the app lifetime, so
/// dispose() is rarely called — but it keeps tests hermetic and prevents
/// resource warnings in strict analysis modes.
final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService();
  ref.onDispose(() => service.dispose().ignore());
  return service;
});

/// Stream provider for the current authenticated [VextUser].
/// Emits null when logged out, VextUser when logged in.
///
/// Uses Firestore snapshots() internally — fires on role updates and any
/// document change, not just login/logout. The router uses this for reactive
/// role-based redirects. Do NOT use this in service providers that must
/// remain stable across Firestore writes — use [firebaseUidProvider] instead.
final authStateProvider = StreamProvider<VextUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Emits the raw Firebase Auth UID on login/logout ONLY.
///
/// Unlike [authStateProvider], this stream does NOT fire when the Firestore
/// user document changes (role updates, key uploads, etc.). It is backed
/// directly by [FirebaseAuth.authStateChanges], which only emits on actual
/// authentication events.
///
/// Use this in long-lived service providers (e.g. [attendanceServiceProvider])
/// so they are only destroyed and recreated on real session boundaries, not
/// on every Firestore write.
final firebaseUidProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance
      .authStateChanges()
      .map((user) => user?.uid);
});
