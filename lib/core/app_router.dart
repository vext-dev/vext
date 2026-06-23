import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_service_provider.dart';
import '../services/auth_service.dart'; // VextUser type used in _RouterNotifier
import '../screens/auth/login_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/test_screen.dart'; // TODO: remove after Milestone 3 testing is complete
import '../lanes/attendance/screens/teacher_session_screen.dart';
import '../lanes/attendance/screens/student_attendance_screen.dart';
import '../lanes/sos/screens/sos_screen.dart';    // M5 — Lane C
import '../lanes/social/screens/social_screen.dart'; // M6 — Lane B
import '../lanes/social/screens/direct_message_screen.dart'; // M7 — Lane B 1:1 DM

// ── Route path constants ──────────────────────────────────────────────────────

abstract class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String roleSelection = '/role-selection';
  // NOTE: Keep /test route alive until Milestone 3 two-phone peer test is signed off.
  // TODO: remove /test and the TestScreen import after M3 sign-off.
  static const String test = '/test';
  static const String attendance = '/home/attendance';
  // M4 sub-routes — Milestone 4 (Lane A)
  static const String teacherSession = '/home/attendance/teacher-session';
  static const String studentAttendance = '/home/attendance/student';
  // M5 / M6 sub-routes (placeholder — will be filled in those milestones)
  static const String social = '/home/social';
  // M7 sub-route — Lane B 1:1 encrypted DM. Relative segment is 'dm/:peerUid';
  // navigate with context.push('$social/dm/$peerUid', extra: peerName).
  static const String socialDirectMessage = '/home/social/dm';
  static const String sos = '/home/sos';
  static const String profile = '/home/profile';
  // NOTE(logout): Logout is available from:
  //   • TestScreen AppBar (M3 testing) — already wired
  //   • ProfileScreen bottom button (M4+) — already wired
  //   These two entry points must remain functional in every milestone.
}

// ── RouterNotifier ────────────────────────────────────────────────────────────

/// Bridges Riverpod's [authStateProvider] to GoRouter's [refreshListenable].
///
/// WHY THIS EXISTS (Bug fix — GoRouter recreation):
/// The previous pattern was:
///   final routerProvider = Provider<GoRouter>((ref) {
///     final authState = ref.watch(authStateProvider);   // dependency
///     return GoRouter(...);                             // new instance every time
///   });
///
/// Because [authStateProvider] uses Firestore snapshots(), it fires on EVERY
/// Firestore document write — not just login/logout. This caused a brand-new
/// GoRouter to be created multiple times per session, destroying the navigation
/// stack and causing the sign-out redirect loop (user was sent back to attendance
/// because the router saw a logged-in user navigating to /login).
///
/// The fix: create the GoRouter ONCE. [_RouterNotifier] listens to auth state
/// and calls [notifyListeners()] to trigger GoRouter's built-in redirect
/// re-evaluation without rebuilding or replacing the router instance.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    // Listen (not watch) — this fires notifyListeners() on every auth state
    // change without making _RouterNotifier itself a reactive dependency.
    ref.listen<AsyncValue<VextUser?>>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final _routerNotifierProvider = Provider<_RouterNotifier>((ref) {
  return _RouterNotifier(ref);
});

// ── Router provider ───────────────────────────────────────────────────────────

/// Stable GoRouter instance — created ONCE for the app lifetime.
///
/// Auth-state changes trigger redirect re-evaluation via [refreshListenable],
/// NOT by recreating the router. Navigation stack is preserved across auth
/// events (e.g. Firestore document writes during role selection).
final routerProvider = Provider<GoRouter>((ref) {
  // Watch the notifier so this provider stays alive as long as the notifier does.
  // The notifier's ChangeNotifier.notifyListeners() drives GoRouter's redirect.
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,

    // refreshListenable: when notifier fires, GoRouter re-runs redirect()
    // without destroying or replacing the router instance.
    refreshListenable: notifier,

    redirect: (context, state) {
      // Read (not watch) — we are already notified via refreshListenable.
      // Using ref.read here avoids a second reactive dependency chain.
      final authState = ref.read(authStateProvider);

      // Still loading Firebase auth — keep showing splash, do nothing.
      if (authState.isLoading) return null;

      final user = authState.valueOrNull;
      final isLoggedIn = user != null;
      // Empty role ('') means user is authenticated but has not yet chosen a
      // role. The router sends them to RoleSelectionScreen in this state.
      final hasRole = (user?.role ?? '').isNotEmpty;
      final path = state.uri.toString();

      // Pages that are accessible without a role — login and signup only.
      // NOTE: roleSelection is intentionally NOT in this list so that a
      // logged-in user with a role is redirected away from it (no re-selection).
      final isAuthPage =
          path == AppRoutes.login || path == AppRoutes.signup;

      // ── Splash ──────────────────────────────────────────────────────────
      // Splash is a loading placeholder — never a final destination.
      if (path == AppRoutes.splash) {
        if (!isLoggedIn) return AppRoutes.login;
        if (!hasRole) return AppRoutes.roleSelection;
        return AppRoutes.attendance;
      }

      // ── Not authenticated ────────────────────────────────────────────────
      // Unauthenticated users reaching any protected route → login.
      if (!isLoggedIn && !isAuthPage) return AppRoutes.login;

      // ── Authenticated, no role ───────────────────────────────────────────
      // Force role selection unless already there.
      if (isLoggedIn && !hasRole && path != AppRoutes.roleSelection) {
        return AppRoutes.roleSelection;
      }

      // ── Authenticated, has role ──────────────────────────────────────────
      // Don't allow re-visiting roleSelection once a role is set.
      if (isLoggedIn && hasRole && path == AppRoutes.roleSelection) {
        return AppRoutes.attendance;
      }

      // Don't allow returning to login/signup once authenticated + has role.
      if (isLoggedIn && hasRole && isAuthPage) {
        return AppRoutes.attendance;
      }

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
            routes: [
              // M4 — Lane A sub-routes (navigate with context.push)
              GoRoute(
                path: 'teacher-session',
                builder: (context, state) => const TeacherSessionScreen(),
              ),
              GoRoute(
                path: 'student',
                builder: (context, state) => const StudentAttendanceScreen(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.social,
            builder: (context, state) => const SocialScreen(), // M6 — Lane B
            routes: [
              // M7 — Lane B 1:1 encrypted DM (navigate with context.push)
              GoRoute(
                path: 'dm/:peerUid',
                builder: (context, state) {
                  final peerUid = state.pathParameters['peerUid']!;
                  final peerName =
                      state.extra is String ? state.extra as String : null;
                  return DirectMessageScreen(
                    peerUid: peerUid,
                    peerName: peerName,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.sos,
            builder: (context, state) => const SosScreen(),
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

// _PlaceholderScreen was removed — all lanes (Attendance, Social, SOS, Profile)
// are now fully implemented. If a future milestone needs a stub screen, add a
// new dedicated class here rather than reusing a generic placeholder.
