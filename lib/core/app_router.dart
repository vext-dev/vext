import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_service_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/test_screen.dart'; // TODO: remove after Milestone 3 testing

// ── Route path constants ──────────────────────────────────────────────────────

abstract class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String roleSelection = '/role-selection';
  // TODO: remove /test after Milestone 3 testing is complete
  static const String test = '/test';
  static const String attendance = '/home/attendance';
  static const String social = '/home/social';
  static const String sos = '/home/sos';
  static const String profile = '/home/profile';
}

// ── Router provider ───────────────────────────────────────────────────────────

/// GoRouter wrapped in a Riverpod provider so it can watch auth state
/// and trigger redirects automatically on sign-in / sign-out.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,

    redirect: (context, state) {
      // Still loading Firebase auth — keep showing splash, do nothing.
      if (authState.isLoading) return null;

      final isLoggedIn = authState.valueOrNull != null;
      final path = state.uri.toString();

      // Splash is only a loading placeholder — never a final destination.
      // Once auth state is known, always navigate away from it.
      if (path == AppRoutes.splash) {
        // TODO: change AppRoutes.test → AppRoutes.attendance after M3 testing
        return isLoggedIn ? AppRoutes.test : AppRoutes.login;
      }

      final isAuthPage = path == AppRoutes.login ||
          path == AppRoutes.signup ||
          path == AppRoutes.roleSelection;

      // Not logged in and trying to reach a protected route → force to login.
      if (!isLoggedIn && !isAuthPage) return AppRoutes.login;

      // Logged in but still on an auth page → go to test screen (M3 testing).
      // TODO: change AppRoutes.test → AppRoutes.attendance after M3 testing
      if (isLoggedIn && isAuthPage) return AppRoutes.test;

      return null;
    },

    routes: [
      // ── Splash ──────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),

      // ── Mesh test screen (Milestone 3 testing only) ──────────────────────────
      // TODO: remove this route after M3 testing is complete
      GoRoute(
        path: AppRoutes.test,
        builder: (context, state) => const TestScreen(),
      ),

      // ── Auth flow ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.roleSelection,
        builder: (context, state) => const RoleSelectionScreen(),
      ),

      // ── Main app with bottom nav shell ────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => AppShellScreen(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.attendance,
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: AppRoutes.social,
            builder: (context, state) =>
                const _PlaceholderScreen(label: 'Social — Coming in Week 3'),
          ),
          GoRoute(
            path: AppRoutes.sos,
            builder: (context, state) =>
                const _PlaceholderScreen(label: 'SOS — Coming in Week 3'),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.uri}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    ),
  );
});

// ── Splash screen (shown while Firebase initialises) ─────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'VEXT',
              style: TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'VigilantMesh',
              style: TextStyle(
                color: Color(0xFF8BA3C0),
                fontSize: 14,
                letterSpacing: 3,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(
              color: Color(0xFF3B82F6),
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Placeholder for lanes not yet implemented ─────────────────────────────────

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.construction, color: Color(0xFF4D7096), size: 48),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8BA3C0), fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
