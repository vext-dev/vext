import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

/// Singleton provider for [AuthService].
/// All widgets that need auth operations read this.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Stream provider for the current authenticated [VextUser].
/// Emits null when logged out, VextUser when logged in.
/// The router listens to this to decide where to redirect.
final authStateProvider = StreamProvider<VextUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});
