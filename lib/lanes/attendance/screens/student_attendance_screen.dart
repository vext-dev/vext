// ── StudentAttendanceScreen — VEXT Lane A Student View ───────────────────────
//
// Shows the student:
//   1. Current auto-detection status (Idle / Detecting / Marked Present / Error).
//   2. A history of sessions where they were marked present (from Drift DB).
//
// AttendanceService wires the mesh streams on initialize(). This screen just
// subscribes to the status stream and watches the Drift DB for proof history.
//
// The student does NOT need to tap anything — attendance is fully automatic.
// They keep the app open and Bluetooth on; the rest happens in the background.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_theme.dart';
import '../../../lanes/attendance/attendance_service.dart';
import '../../../providers/attendance_service_provider.dart';
import '../../../providers/ble_provider.dart';

class StudentAttendanceScreen extends ConsumerWidget {
  const StudentAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleStateProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          'Attendance',
          style: TextStyle(
            color: AppTheme.primaryColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: const BackButton(color: AppTheme.secondaryTextColor),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── BLE status warning ─────────────────────────────────────
              if (!bleState.isActive) ...[
                _BleWarningBanner(),
                const SizedBox(height: 16),
              ],

              // ── Detection status card (live stream) ────────────────────
              _AttendanceStatusCard(),
              const SizedBox(height: 24),

              // ── Session history ────────────────────────────────────────
              const Text(
                'RECENT SESSIONS',
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Expanded(child: _ProofHistoryList()),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Attendance status card ────────────────────────────────────────────────────

class _AttendanceStatusCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AttendanceStatusCard> createState() =>
      _AttendanceStatusCardState();
}

class _AttendanceStatusCardState
    extends ConsumerState<_AttendanceStatusCard> {
  AttendanceStatus _status = const AttendanceStatus.idle();

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(attendanceServiceProvider);

    return attendanceAsync.when(
      loading: () => _buildCard(const AttendanceStatus.idle()),
      error: (e, _) => _buildCard(AttendanceStatus(
        type: AttendanceStatusType.error,
        error: e.toString(),
      )),
      data: (svc) => StreamBuilder<AttendanceStatus>(
        stream: svc.attendanceStatusStream,
        initialData: _status,
        builder: (context, snapshot) {
          final status = snapshot.data ?? const AttendanceStatus.idle();
          return _buildCard(status);
        },
      ),
    );
  }

  Widget _buildCard(AttendanceStatus status) {
    final (icon, iconColor, label, sublabel, bgColor, borderColor) =
        _resolveStyle(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sublabel,
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String, String, Color, Color) _resolveStyle(
      AttendanceStatus status) {
    switch (status.type) {
      case AttendanceStatusType.idle:
        return (
          Icons.bluetooth_searching_rounded,
          AppTheme.primaryColor,
          'Listening…',
          'Keep the app open. Attendance is marked automatically when you\'re in range.',
          AppTheme.cardColor,
          AppTheme.inputBorderColor,
        );
      case AttendanceStatusType.detecting:
        return (
          Icons.sensors_rounded,
          const Color(0xFFF59E0B), // amber
          'Session Detected',
          'Verifying proximity and assembling proof…',
          const Color(0xFFF59E0B).withValues(alpha: 0.08),
          const Color(0xFFF59E0B).withValues(alpha: 0.4),
        );
      case AttendanceStatusType.markedPresent:
        return (
          Icons.check_circle_rounded,
          AppTheme.successColor,
          'Marked Present ✓',
          status.sessionId != null
              ? 'Session ${status.sessionId!.substring(0, 8)}… · Signal: ${status.rssi == 0 ? "GATT" : "${status.rssi} dBm"}'
              : 'Attendance recorded.',
          AppTheme.successColor.withValues(alpha: 0.08),
          AppTheme.successColor.withValues(alpha: 0.4),
        );
      case AttendanceStatusType.error:
        return (
          Icons.error_outline_rounded,
          AppTheme.errorColor,
          'Error',
          status.error ?? 'An unknown error occurred.',
          AppTheme.errorColor.withValues(alpha: 0.08),
          AppTheme.errorColor.withValues(alpha: 0.4),
        );
    }
  }
}

// ── Proof history (Drift watch) ───────────────────────────────────────────────

class _ProofHistoryList extends ConsumerWidget {
  const _ProofHistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(attendanceServiceProvider);

    return attendanceAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      error: (e, _) => Center(
        child: Text('$e',
            style: const TextStyle(color: AppTheme.errorColor)),
      ),
      data: (svc) {
        // We watch the db directly via a StreamBuilder from the service.
        // For simplicity, use a one-time fetch + manual refresh pattern.
        // In M7 we will wire a proper Drift watch here.
        return _ProofHistoryBuilder(svc: svc);
      },
    );
  }
}

class _ProofHistoryBuilder extends ConsumerWidget {
  const _ProofHistoryBuilder({required this.svc});
  final AttendanceService svc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen to status updates so the history section rebuilds when a new
    // proof is saved (e.g. after being marked present in a session).
    return StreamBuilder<AttendanceStatus>(
      stream: svc.attendanceStatusStream,
      builder: (context, snapshot) {
        final status = snapshot.data;

        // Milestone 4 — full proof history (live Drift watch per session)
        // will be added in Milestone 7 when student gets a profile history page.
        // For now: show a contextual empty state or a "marked present" card.
        if (status?.type == AttendanceStatusType.markedPresent) {
          return _MarkedPresentCard(status: status!);
        }

        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded,
                  size: 40, color: AppTheme.hintTextColor),
              SizedBox(height: 12),
              Text(
                'Session history will appear here\nonce you\'ve been marked present.',
                style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 13,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MarkedPresentCard extends StatelessWidget {
  const _MarkedPresentCard({required this.status});
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppTheme.successColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppTheme.successColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Present',
                  style: TextStyle(
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                if (status.sessionId != null)
                  Text(
                    'Session: ${status.sessionId!.substring(0, 8)}…',
                    style: const TextStyle(
                        color: AppTheme.hintTextColor,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
              ],
            ),
          ),
          const Icon(Icons.cloud_upload_outlined,
              size: 18, color: AppTheme.hintTextColor),
        ],
      ),
    );
  }
}

// ── BLE warning ───────────────────────────────────────────────────────────────

class _BleWarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.bluetooth_disabled_rounded,
              color: Color(0xFFF59E0B), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bluetooth scanning is not active. Open the app fully to start.',
              style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
