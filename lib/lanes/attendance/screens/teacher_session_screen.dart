// ── TeacherSessionScreen — VEXT Lane A Teacher View ───────────────────────────
//
// Allows a teacher to:
//   1. Enter a course ID and start an attendance session.
//   2. See the session status (broadcasting / stopped).
//   3. Watch a live list of student proofs as they arrive.
//   4. Stop the session when done.
//
// The screen accesses AttendanceService via attendanceServiceProvider.
// Proof list is driven by a Firestore snapshots() stream (watchFirestoreProofs)
// so the teacher sees students the moment their proof is synced to Firestore,
// regardless of BLE proximity to the teacher's device.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_constants.dart';
import '../../../core/app_theme.dart';
import '../../../lanes/attendance/attendance_service.dart';
import '../../../providers/attendance_service_provider.dart';
// drift_service import removed — _ProofTile now uses Firestore Map data, not Drift AttendanceProof row

class TeacherSessionScreen extends ConsumerStatefulWidget {
  const TeacherSessionScreen({super.key});

  @override
  ConsumerState<TeacherSessionScreen> createState() =>
      _TeacherSessionScreenState();
}

class _TeacherSessionScreenState extends ConsumerState<TeacherSessionScreen> {
  final _courseController = TextEditingController(text: 'CS101');
  final _formKey = GlobalKey<FormState>();

  AttendanceSession? _session;
  bool _starting = false;
  bool _stopping = false;
  String? _error;

  @override
  void dispose() {
    _courseController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final svc = await ref.read(attendanceServiceProvider.future);
      final session =
          await svc.startSession(_courseController.text.trim());
      if (mounted) setState(() => _session = session);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopSession() async {
    setState(() {
      _stopping = true;
      _error = null;
    });

    try {
      final svc = await ref.read(attendanceServiceProvider.future);
      await svc.stopSession();
      if (mounted) setState(() => _session = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          'Teacher — Attendance',
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
              // ── Status card ───────────────────────────────────────────────
              _StatusCard(session: _session),
              const SizedBox(height: 20),

              // ── Course input + start/stop ──────────────────────────────
              if (_session == null) ...[
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _courseController,
                    style: const TextStyle(color: AppTheme.primaryTextColor),
                    decoration: const InputDecoration(
                      labelText: 'Course ID',
                      labelStyle:
                          TextStyle(color: AppTheme.secondaryTextColor),
                      hintText: 'e.g. CS101',
                      prefixIcon: Icon(Icons.school_outlined,
                          color: AppTheme.secondaryTextColor),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a course ID' : null,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _starting ? null : _startSession,
                    icon: _starting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_starting ? 'Starting…' : 'Start Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _stopping ? null : _stopSession,
                    icon: _stopping
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.errorColor),
                          )
                        : const Icon(Icons.stop_circle_outlined),
                    label: Text(_stopping ? 'Stopping…' : 'Stop Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                      side: const BorderSide(color: AppTheme.errorColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],

              // ── Error display ─────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error!),
              ],

              const SizedBox(height: 24),

              // ── Proof list ────────────────────────────────────────────
              if (_session != null) ...[
                const Text(
                  'PRESENT',
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _ProofList(sessionId: _session!.id),
                ),
              ] else ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.how_to_reg_outlined,
                          size: 52,
                          color: AppTheme.hintTextColor.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Start a session to begin taking attendance.',
                          style: TextStyle(
                              color: AppTheme.hintTextColor, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.session});

  final AttendanceSession? session;

  @override
  Widget build(BuildContext context) {
    final isActive = session != null && session!.isActive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.successColor.withValues(alpha: 0.1)
            : AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppTheme.successColor.withValues(alpha: 0.4)
              : AppTheme.inputBorderColor,
        ),
      ),
      child: Row(
        children: [
          // Pulsing dot when active
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppTheme.successColor : AppTheme.hintTextColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? 'Broadcasting — ${session!.courseId}'
                      : 'No active session',
                  style: TextStyle(
                    color: isActive
                        ? AppTheme.successColor
                        : AppTheme.secondaryTextColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Session: ${session!.id.substring(0, 8)}…',
                    style: const TextStyle(
                      color: AppTheme.hintTextColor,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live proof list (Firestore stream) ───────────────────────────────────────
//
// Uses AttendanceService.watchFirestoreProofs() — a real-time Firestore
// snapshots() listener on attendance/{sessionId}/proofs.
//
// Why Firestore and not local Drift DB?
//   Student proofs are written to the STUDENT'S local Drift DB, then synced
//   to Firestore by the student's FirebaseSyncEngine. The teacher's local DB
//   is empty. Watching Firestore ensures the teacher sees all students the
//   moment their proof is uploaded, regardless of BLE range.

class _ProofList extends ConsumerWidget {
  const _ProofList({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(attendanceServiceProvider);

    return attendanceAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppTheme.errorColor))),
      data: (svc) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: svc.watchFirestoreProofs(sessionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Text(
                'Connecting to Firestore…',
                style: TextStyle(color: AppTheme.hintTextColor),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: AppTheme.errorColor, fontSize: 12),
              ),
            );
          }

          final proofs = snapshot.data ?? [];

          if (proofs.isEmpty) {
            return const Center(
              child: Text(
                'No students marked yet.\nMake sure students have the app open.',
                style:
                    TextStyle(color: AppTheme.secondaryTextColor, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            itemCount: proofs.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              color: AppTheme.inputBorderColor,
              indent: 56,
            ),
            itemBuilder: (context, index) {
              return _ProofTile(data: proofs[index]);
            },
          );
        },
      ),
    );
  }
}

// ── ProofTile — shows student name resolved from Firestore users collection ──────
//
// Converted to StatefulWidget so the Future is created once in initState and
// never recreated on rebuild (avoids name flicker on list scroll or parent rebuild).
//
// Name lookup: Firestore users/{studentUid} → 'name' field.
// Falls back to truncated UID if: network error, document missing, name empty.
// The avatar shows the student's initials once the name resolves.

class _ProofTile extends StatefulWidget {
  const _ProofTile({required this.data});

  /// Firestore document data — fields written by FirebaseSyncEngine:
  ///   studentUid (String), rssi (int), timestamp (Timestamp), syncedAt (Timestamp)
  final Map<String, dynamic> data;

  @override
  State<_ProofTile> createState() => _ProofTileState();
}

class _ProofTileState extends State<_ProofTile> {
  // Future is stored as a field so it is only created once per tile lifetime,
  // not on every rebuild. This prevents the "loading flash" on list scroll.
  late final Future<String> _nameFuture;

  @override
  void initState() {
    super.initState();
    final uid = widget.data['studentUid'] as String? ?? '';
    _nameFuture = _fetchStudentName(uid);
  }

  /// One-time Firestore read: users/{uid} → name field.
  /// Returns the display name, or the UID as fallback on any failure.
  Future<String> _fetchStudentName(String uid) async {
    if (uid.isEmpty) return '—';
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.fsUsers)
          .doc(uid)
          .get();
      final name = (doc.data()?['name'] as String?)?.trim() ?? '';
      // Return name if non-empty, otherwise fall back to uid.
      return name.isNotEmpty ? name : uid;
    } catch (_) {
      // Network error or permission denied — show uid as fallback.
      return uid;
    }
  }

  /// Extracts up to 2 initials from a display name.
  /// "John Doe" → "JD", "Jane" → "J", "" → "?" (fallback).
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Whether [value] looks like a raw Firebase UID (no spaces, 28 chars).
  bool _isUid(String value) =>
      value.length >= 20 && !value.contains(' ');

  String _formatTime(dynamic rawTs) {
    DateTime dt;
    try {
      dt = (rawTs as dynamic).toDate() as DateTime;
    } catch (_) {
      dt = DateTime.now();
    }
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final studentUid = widget.data['studentUid'] as String? ?? '—';
    final rssi       = widget.data['rssi'] as int? ?? 0;
    final rssiText   = rssi == 0 ? 'GATT' : '$rssi dBm';
    final timestamp  = widget.data['timestamp'];

    // Truncated UID used as placeholder while the name loads.
    final uidShort = studentUid.length > 16
        ? '${studentUid.substring(0, 16)}…'
        : studentUid;

    return FutureBuilder<String>(
      future: _nameFuture,
      builder: (context, snapshot) {
        // While loading, show the UID (same as before). On resolve, show name.
        final displayName = snapshot.data ?? uidShort;
        final resolved    = snapshot.connectionState == ConnectionState.done;
        // Show initials in avatar only once the name is resolved AND it looks
        // like a real name (not a fallback UID).
        final showInitials = resolved && !_isUid(displayName);

        return Container(
          color: AppTheme.cardColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // ── Avatar ─────────────────────────────────────────────────
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: showInitials
                      ? Text(
                          _initials(displayName),
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        )
                      : const Icon(Icons.person_outline,
                          color: AppTheme.primaryColor, size: 20),
                ),
              ),
              const SizedBox(width: 12),

              // ── Name + signal ───────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: AppTheme.primaryTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Signal: $rssiText  ·  ${_formatTime(timestamp)}',
                      style: const TextStyle(
                          color: AppTheme.secondaryTextColor, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // ── Synced indicator ────────────────────────────────────────
              // Always true here — docs only appear after Firestore write.
              const Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: AppTheme.successColor,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppTheme.errorColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppTheme.errorColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
