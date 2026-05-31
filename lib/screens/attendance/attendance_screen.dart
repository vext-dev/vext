// ── AttendanceScreen — VEXT Lane A Entry Point ────────────────────────────────
//
// Role-based router: reads the authenticated user's role and pushes to
// either TeacherSessionScreen or StudentAttendanceScreen.
//
// Also starts BLE in session mode (50% duty cycle) when this screen is active,
// ensuring higher scan frequency for faster peer discovery.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_constants.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_service_provider.dart';
import '../../providers/ble_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    // Elevate to session duty cycle (50% scan) while on this screen.
    // Reverts to idle when navigating away (lifecycle handled by BleStateNotifier).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleStateProvider.notifier).startSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: authAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor)),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppTheme.errorColor)),
          ),
          data: (user) {
            final role = user?.role ?? AppConstants.roleStudent;
            return _AttendanceLanding(role: role);
          },
        ),
      ),
    );
  }
}

// ── Landing — role-based UI ───────────────────────────────────────────────────

class _AttendanceLanding extends StatelessWidget {
  const _AttendanceLanding({required this.role});

  final String role;

  bool get _isTeacher => role == AppConstants.roleTeacher;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Row(
            children: [
              const Text(
                'ATTENDANCE',
                style: TextStyle(
                  color: AppTheme.primaryTextColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              _RoleBadge(role: role),
            ],
          ),
          const SizedBox(height: 32),

          // ── Role-specific card ─────────────────────────────────────
          _RoleCard(isTeacher: _isTeacher),
          const SizedBox(height: 20),

          // ── CTA button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_isTeacher) {
                  context.push('/home/attendance/teacher-session');
                } else {
                  context.push('/home/attendance/student');
                }
              },
              icon: Icon(
                _isTeacher
                    ? Icons.play_circle_outline_rounded
                    : Icons.sensors_rounded,
              ),
              label: Text(
                _isTeacher ? 'Start Session' : 'View Status',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isTeacher ? AppTheme.successColor : AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── How it works ─────────────────────────────────────────
          const _HowItWorks(),
        ],
      ),
    );
  }
}

// ── Role card ─────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.isTeacher});
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.inputBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
            ),
            child: Icon(
              isTeacher
                  ? Icons.cast_connected_outlined
                  : Icons.bluetooth_searching_rounded,
              color: AppTheme.primaryColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTeacher ? 'Teacher Mode' : 'Student Mode',
                  style: const TextStyle(
                    color: AppTheme.primaryTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isTeacher
                      ? 'Start a session to broadcast your presence via BLE mesh. Students in range are marked automatically.'
                      : 'Stay on this screen with Bluetooth on. The app marks your attendance automatically when in range of a teacher.',
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── How it works ─────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HOW IT WORKS',
          style: TextStyle(
            color: AppTheme.secondaryTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        _Step(
          number: '1',
          text: 'Teacher opens this screen and taps "Start Session".',
        ),
        _Step(
          number: '2',
          text:
              'The app broadcasts an attendance beacon via Bluetooth mesh.',
        ),
        _Step(
          number: '3',
          text:
              'Students\' phones receive the beacon and auto-submit a proof of presence.',
        ),
        _Step(
          number: '4',
          text:
              'Proofs sync to the cloud when internet is available.',
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.35)),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 13,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Role badge ────────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  Color get _color {
    switch (role.toLowerCase()) {
      case 'teacher':
        return const Color(0xFF8B5CF6);
      case 'security':
        return const Color(0xFFF59E0B);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        role.isEmpty ? '—' : role[0].toUpperCase() + role.substring(1),
        style: TextStyle(
            color: _color,
            fontSize: 12,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
