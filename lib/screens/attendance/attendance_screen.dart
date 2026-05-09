import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_record.dart'; // AttendanceRecord (Isar model)
import '../models/session_record.dart'; // SessionRecord (Isar model)
import '../models/student_presence.dart'; // StudentPresence (PROOF packet data)
import '../providers/attendance_provider.dart';
import '../providers/auth_service_provider.dart';
import '../providers/session_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Root screen — branches on role
// ─────────────────────────────────────────────────────────────────────────────

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        backgroundColor: _AC.background,
        body: Center(
          child: CircularProgressIndicator(color: _AC.accent),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: _AC.background,
        body: Center(
          child: Text(
            'Failed to load profile',
            style: TextStyle(color: _AC.danger),
          ),
        ),
      ),
      data: (profile) {
        if (profile.role.toLowerCase() == 'teacher') {
          return const _TeacherView();
        }
        return const _StudentView();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEACHER VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherView extends ConsumerStatefulWidget {
  const _TeacherView();

  @override
  ConsumerState<_TeacherView> createState() => _TeacherViewState();
}

class _TeacherViewState extends ConsumerState<_TeacherView> {
  final _courseController = TextEditingController();
  bool _sessionLoading = false;

  // Stopwatch state
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void dispose() {
    _courseController.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _elapsed = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  String get _formattedElapsed {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _handleStartSession() async {
    final courseId = _courseController.text.trim();
    if (courseId.isEmpty) {
      _showSnackBar('Please enter a Course ID.', isError: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sessionLoading = true);
    try {
      await ref.read(sessionProvider.notifier).startSession(courseId: courseId);
      _startTicker();
    } catch (e) {
      _showSnackBar('Failed to start session. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  Future<void> _handleStopSession() async {
    setState(() => _sessionLoading = true);
    try {
      await ref.read(sessionProvider.notifier).stopSession();
      _stopTicker();
      setState(() => _elapsed = Duration.zero);
    } catch (e) {
      _showSnackBar('Failed to stop session. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  void _showSnackBar(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _AC.danger : _AC.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isActive = session?.isActive ?? false;
    final roster = ref.watch(liveRosterProvider); // List<StudentPresence>
    final history = ref.watch(sessionHistoryProvider); // List<SessionRecord>

    return Scaffold(
      backgroundColor: _AC.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ScreenLabel(label: 'ATTENDANCE', role: 'Teacher'),
                    const SizedBox(height: 24),

                    // Session control card
                    _TeacherSessionCard(
                      courseController: _courseController,
                      isActive: isActive,
                      isLoading: _sessionLoading,
                      sessionId: session?.sessionId,
                      elapsed: _formattedElapsed,
                      onStart: _handleStartSession,
                      onStop: _handleStopSession,
                    ),
                    const SizedBox(height: 24),

                    // Live roster
                    if (isActive) ...[
                      _LiveRoster(roster: roster),
                      const SizedBox(height: 24),
                    ],

                    // Section header
                    _SectionHeader(title: 'Session History'),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ── Session history ───────────────────────────────────────
            history.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child:
                      Center(child: CircularProgressIndicator(color: _AC.accent)),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: _EmptyState(
                  icon: Icons.error_outline,
                  message: 'Could not load history.',
                ),
              ),
              data: (records) => records.isEmpty
                  ? SliverToBoxAdapter(
                      child: _EmptyState(
                        icon: Icons.history_edu_outlined,
                        message: 'No sessions yet.',
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _SessionHistoryRow(record: records[i]),
                          childCount: records.length,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Teacher session card ──────────────────────────────────────────────────────

class _TeacherSessionCard extends StatelessWidget {
  const _TeacherSessionCard({
    required this.courseController,
    required this.isActive,
    required this.isLoading,
    required this.sessionId,
    required this.elapsed,
    required this.onStart,
    required this.onStop,
  });

  final TextEditingController courseController;
  final bool isActive;
  final bool isLoading;
  final String? sessionId;
  final String elapsed;
  final VoidCallback onStart;
  final VoidCallback onStop;

  String get _shortSessionId {
    if (sessionId == null) return '—';
    return sessionId!.length > 12
        ? '${sessionId!.substring(0, 12)}…'
        : sessionId!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isActive
            ? _AC.success.withOpacity(0.07)
            : _AC.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? _AC.success.withOpacity(0.4) : _AC.cardBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? _AC.success.withOpacity(0.12)
                : Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isActive
          ? _ActiveSessionContent(
              shortId: _shortSessionId,
              elapsed: elapsed,
              isLoading: isLoading,
              onStop: onStop,
            )
          : _StartSessionContent(
              courseController: courseController,
              isLoading: isLoading,
              onStart: onStart,
            ),
    );
  }
}

class _StartSessionContent extends StatelessWidget {
  const _StartSessionContent({
    required this.courseController,
    required this.isLoading,
    required this.onStart,
  });

  final TextEditingController courseController;
  final bool isLoading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'New Session',
          style: TextStyle(
            color: _AC.title,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: courseController,
          style: const TextStyle(color: _AC.title, fontSize: 14),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onStart(),
          decoration: InputDecoration(
            hintText: 'Course ID (e.g. CS101)',
            hintStyle:
                TextStyle(color: _AC.subtitle.withOpacity(0.6), fontSize: 14),
            prefixIcon: const Icon(Icons.class_outlined,
                color: _AC.iconColor, size: 18),
            filled: true,
            fillColor: _AC.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _AC.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _AC.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: _AC.accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onStart,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_circle_outline, size: 22),
            label: Text(isLoading ? 'Starting…' : 'Start Session'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _AC.success,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _AC.success.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveSessionContent extends StatelessWidget {
  const _ActiveSessionContent({
    required this.shortId,
    required this.elapsed,
    required this.isLoading,
    required this.onStop,
  });

  final String shortId;
  final String elapsed;
  final bool isLoading;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Live pulse dot
            _PulsingDot(color: _AC.success),
            const SizedBox(width: 10),
            const Text(
              'Session Active',
              style: TextStyle(
                color: _AC.success,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatPill(
                label: 'Session ID',
                value: shortId,
                icon: Icons.tag,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatPill(
                label: 'Duration',
                value: elapsed,
                icon: Icons.timer_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onStop,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.stop_circle_outlined, size: 20),
            label: Text(isLoading ? 'Stopping…' : 'Stop Session'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _AC.danger,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _AC.danger.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Live roster ───────────────────────────────────────────────────────────────

class _LiveRoster extends StatelessWidget {
  const _LiveRoster({required this.roster});

  final List<StudentPresence> roster;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionHeader(title: 'Live Roster'),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _AC.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _AC.success.withOpacity(0.4)),
              ),
              child: Text(
                '${roster.length} present',
                style: const TextStyle(
                  color: _AC.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (roster.isEmpty)
          _EmptyState(
            icon: Icons.people_outline,
            message: 'Waiting for students to check in…',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: _AC.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _AC.cardBorder),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: roster.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1, color: _AC.cardBorder, indent: 60),
              itemBuilder: (ctx, i) =>
                  _StudentPresenceRow(presence: roster[i]),
            ),
          ),
      ],
    );
  }
}

class _StudentPresenceRow extends StatelessWidget {
  const _StudentPresenceRow({required this.presence});

  final StudentPresence presence;

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Avatar initials
          CircleAvatar(
            radius: 18,
            backgroundColor: _AC.accent.withOpacity(0.15),
            child: Text(
              presence.studentName.isNotEmpty
                  ? presence.studentName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: _AC.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + timestamp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presence.studentName,
                  style: const TextStyle(
                    color: _AC.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(presence.timestamp),
                  style: const TextStyle(
                    color: _AC.subtitle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // RSSI
          _RssiBadge(rssi: presence.rssi),
          const SizedBox(width: 8),

          // Verified badge
          if (presence.isVerified)
            const Tooltip(
              message: 'Cryptographically verified',
              child: Icon(Icons.verified, color: _AC.success, size: 18),
            )
          else
            Icon(Icons.help_outline, color: _AC.subtitle, size: 18),
        ],
      ),
    );
  }
}

// ── Session history row ───────────────────────────────────────────────────────

class _SessionHistoryRow extends StatelessWidget {
  const _SessionHistoryRow({required this.record});

  final SessionRecord record;

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _AC.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AC.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _AC.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.history_edu_outlined,
                color: _AC.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.courseId,
                  style: const TextStyle(
                    color: _AC.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatDate(record.startedAt)} · '
                  '${_formatTime(record.startedAt)} – '
                  '${record.endedAt != null ? _formatTime(record.endedAt!) : 'ongoing'}',
                  style: const TextStyle(
                    color: _AC.subtitle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${record.presentCount} students',
            style: const TextStyle(
              color: _AC.success,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDENT VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _StudentView extends ConsumerWidget {
  const _StudentView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestMark = ref.watch(latestAttendanceMarkProvider);
    final history = ref.watch(myAttendanceHistoryProvider);

    return Scaffold(
      backgroundColor: _AC.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ScreenLabel(label: 'ATTENDANCE', role: 'Student'),
                    const SizedBox(height: 24),

                    // Status / success card
                    latestMark != null
                        ? _AttendanceMarkedCard(record: latestMark)
                        : const _ListeningCard(),

                    const SizedBox(height: 28),
                    _SectionHeader(title: 'My History'),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ── History list ──────────────────────────────────────────
            history.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child:
                      Center(child: CircularProgressIndicator(color: _AC.accent)),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: _EmptyState(
                  icon: Icons.error_outline,
                  message: 'Could not load history.',
                ),
              ),
              data: (records) => records.isEmpty
                  ? SliverToBoxAdapter(
                      child: _EmptyState(
                        icon: Icons.event_busy_outlined,
                        message: 'No attendance records yet.',
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) =>
                              _AttendanceHistoryRow(record: records[i]),
                          childCount: records.length,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Listening card ────────────────────────────────────────────────────────────

class _ListeningCard extends StatefulWidget {
  const _ListeningCard();

  @override
  State<_ListeningCard> createState() => _ListeningCardState();
}

class _ListeningCardState extends State<_ListeningCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: _AC.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AC.cardBorder),
        boxShadow: [
          BoxShadow(
            color: _AC.accent.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Pulsing BLE rings
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              return SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ring
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _AC.accent
                            .withOpacity(0.06 * _pulse.value),
                      ),
                    ),
                    // Mid ring
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _AC.accent
                            .withOpacity(0.10 * _pulse.value),
                      ),
                    ),
                    // Core
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _AC.accent.withOpacity(0.18),
                        border: Border.all(
                            color: _AC.accent.withOpacity(0.5), width: 1.5),
                      ),
                      child: const Icon(Icons.bluetooth_searching,
                          color: _AC.accent, size: 20),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Listening for attendance sessions…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _AC.title,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep Bluetooth enabled and stay within\nrange of your teacher\'s device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _AC.subtitle,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Attendance marked card ────────────────────────────────────────────────────

class _AttendanceMarkedCard extends StatefulWidget {
  const _AttendanceMarkedCard({required this.record});

  final AttendanceRecord record;

  @override
  State<_AttendanceMarkedCard> createState() => _AttendanceMarkedCardState();
}

class _AttendanceMarkedCardState extends State<_AttendanceMarkedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    final date = '${dt.day}/${dt.month}/${dt.year}';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$date at $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _AC.success.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _AC.success.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: _AC.success.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Animated checkmark
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _AC.success.withOpacity(0.15),
                  border: Border.all(
                      color: _AC.success.withOpacity(0.5), width: 2),
                ),
                child: const Icon(Icons.check_rounded,
                    color: _AC.success, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Attendance Marked!',
              style: TextStyle(
                color: _AC.success,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 16),

            // Detail pills
            _DetailRow(
              icon: Icons.class_outlined,
              label: 'Course',
              value: widget.record.courseId,
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.access_time_outlined,
              label: 'Time',
              value: _formatDateTime(widget.record.markedAt),
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.signal_cellular_alt_outlined,
              label: 'RSSI',
              value: '${widget.record.rssi} dBm',
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'GPS',
              value: widget.record.gpsStatus,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _AC.success.withOpacity(0.7), size: 15),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(color: _AC.subtitle, fontSize: 13),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _AC.title,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Attendance history row ────────────────────────────────────────────────────

class _AttendanceHistoryRow extends StatelessWidget {
  const _AttendanceHistoryRow({required this.record});

  final AttendanceRecord record;

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _AC.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AC.cardBorder),
      ),
      child: Row(
        children: [
          // Date block
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _AC.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  _formatDate(record.markedAt).split(' ')[0],
                  style: const TextStyle(
                    color: _AC.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _formatDate(record.markedAt).split(' ')[1],
                  style: const TextStyle(
                    color: _AC.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Course + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.courseId,
                  style: const TextStyle(
                    color: _AC.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTime(record.markedAt),
                  style: const TextStyle(color: _AC.subtitle, fontSize: 11),
                ),
              ],
            ),
          ),

          // Status badges
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusBadge(
                label: record.isVerified ? 'Verified' : 'Unverified',
                color: record.isVerified ? _AC.success : _AC.warning,
              ),
              const SizedBox(height: 4),
              _StatusBadge(
                label: record.isSynced ? 'Synced' : 'Pending',
                color: record.isSynced ? _AC.accent : _AC.subtitle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ScreenLabel extends StatelessWidget {
  const _ScreenLabel({required this.label, required this.role});

  final String label;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _AC.title,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _AC.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _AC.accent.withOpacity(0.3)),
          ),
          child: Text(
            role,
            style: const TextStyle(
              color: _AC.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: _AC.sectionLabel,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _AC.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _AC.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: _AC.subtitle, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _AC.subtitle,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: _AC.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RssiBadge extends StatelessWidget {
  const _RssiBadge({required this.rssi});

  final int rssi;

  Color get _color {
    if (rssi >= -60) return _AC.success;
    if (rssi >= -80) return _AC.warning;
    return _AC.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Text(
        '$rssi dBm',
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, color: _AC.subtitle, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: _AC.subtitle, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _a = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_a.value),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color tokens
// ─────────────────────────────────────────────────────────────────────────────

abstract class _AC {
  static const Color background = Color(0xFF0D1B2A);
  static const Color cardBackground = Color(0xFF132338);
  static const Color cardBorder = Color(0xFF1E3A56);
  static const Color inputFill = Color(0xFF0F2035);

  static const Color accent = Color(0xFF3B82F6);
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const Color title = Color(0xFFE8EEF6);
  static const Color subtitle = Color(0xFF7A94B0);
  static const Color sectionLabel = Color(0xFF4D7096);
  static const Color iconColor = Color(0xFF4D7096);
}
