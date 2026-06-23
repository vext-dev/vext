// ── TeacherSessionScreen — VEXT Lane A Teacher View ───────────────────────────
//
// Allows a teacher to:
//   1. Enter a course ID and start an attendance session.
//   2. See the session status (broadcasting / stopped).
//   3. Watch a live list of student proofs as they arrive.
//   4. Stop the session when done.
//
// Proof source strategy (Fix 4A + 4B):
//   PRIMARY   — Firestore snapshots() when online. Shows every student whose
//               proof has synced, regardless of BLE proximity.
//   FALLBACK  — Local Drift DB watch when Firestore is unavailable (offline,
//               permission-denied before session doc reaches server). Shows
//               students whose devices sent an ACK packet via BLE.
//
// The _ProofList widget tries Firestore first. On permission-denied or any
// Firestore error it switches to Drift and retries Firestore every 15 seconds.
// This means the teacher always sees students — even with no internet.
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_constants.dart';
import '../../../core/app_theme.dart';
import '../../../lanes/attendance/attendance_service.dart';
import '../../../providers/attendance_service_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../services/drift_service.dart';

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

// ── Live proof list — Firestore primary, Drift fallback (Fix 4A + 4B) ─────────
//
// Strategy (connectivity-aware):
//   • Check network connectivity immediately in initState.
//   • If OFFLINE: skip Firestore entirely, go straight to Drift (BLE ACK path).
//     This fixes the core offline bug: Firestore with offline persistence does
//     NOT error when there's no network — it silently waits. snapshot.hasError
//     never becomes true, so the old error-based fallback never triggered.
//   • If ONLINE: use Firestore (shows all students, cloud-synced).
//     On permission-denied or Firestore error, fall back to Drift.
//   • Connectivity listener: switches source reactively when network changes.
//   • Auto-retry Firestore every 15 seconds after an error (non-connectivity
//     failures like permission-denied during session doc race).
//   • A source badge tells the teacher which feed they are seeing.

enum _ProofSource { loading, firestore, localBle, error }

class _ProofList extends ConsumerStatefulWidget {
  const _ProofList({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_ProofList> createState() => _ProofListState();
}

class _ProofListState extends ConsumerState<_ProofList> {
  String? _firestoreError;
  Timer? _retryTimer;
  bool _firestoreFailed = false;

  // Connectivity subscription — reacts to WiFi on/off changes.
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Stream<List<Map<String, dynamic>>>? _firestoreStream;
  Stream<List<AttendanceProof>>? _driftStream;

  @override
  void initState() {
    super.initState();
    // Check connectivity immediately — don't wait for Firestore to fail.
    // Firestore SDK with offline persistence never errors on network loss;
    // it just silently waits. We must detect offline state ourselves.
    _checkConnectivityAndSetSource();

    // Listen for connectivity changes so the source switches automatically
    // when the teacher's phone gains or loses WiFi during a session.
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (!mounted) return;
        final hasNet = results.any((r) => r != ConnectivityResult.none);
        if (hasNet && _firestoreFailed) {
          // Network returned — try Firestore again.
          setState(() {
            _firestoreFailed = false;
            _firestoreStream = null; // fresh subscription
            _firestoreError = null;
          });
        } else if (!hasNet && !_firestoreFailed) {
          // Network lost — drop immediately to Drift (BLE ACK path).
          setState(() {
            _firestoreFailed = true;
            _firestoreStream = null;
            _firestoreError = 'No network — showing BLE-only results';
          });
          _retryTimer?.cancel();
        }
      },
    );
  }

  Future<void> _checkConnectivityAndSetSource() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (!hasNet) {
        setState(() {
          _firestoreFailed = true;
          _firestoreError = 'No network — showing BLE-only results';
        });
      }
    } catch (_) {
      // Connectivity check failure is non-fatal — proceed with Firestore
      // and let it error naturally if offline.
    }
  }

  void _scheduleFirestoreRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() {
        _firestoreFailed = false;
        _firestoreStream = null;
      });
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(attendanceServiceProvider);
    final dbAsync = ref.watch(databaseProvider);

    return attendanceAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppTheme.errorColor))),
      data: (svc) {
        // ── Firestore path ─────────────────────────────────────────────────
        if (!_firestoreFailed) {
          // Initialise stream once (or after a retry reset). Never recreate
          // it on a plain rebuild — doing so re-subscribes every frame.
          _firestoreStream ??= svc.watchFirestoreProofs(widget.sessionId);

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _firestoreStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final err = snapshot.error.toString();
                final isPermissionDenied = err.contains('permission-denied') ||
                    err.contains('PERMISSION_DENIED');

                // Use addPostFrameCallback so we don't call setState inside build().
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _firestoreFailed) return; // guard double-fire
                  setState(() {
                    _firestoreFailed = true;
                    _firestoreStream = null; // will be recreated on retry
                    _firestoreError = isPermissionDenied
                        ? 'Waiting for cloud sync — showing BLE-only results'
                        : 'Firestore unavailable — showing BLE-only results';
                  });
                  _scheduleFirestoreRetry();
                });

                return const Center(
                  child: Text(
                    'Connecting…',
                    style: TextStyle(color: AppTheme.hintTextColor),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Text(
                    'Connecting to Firestore…',
                    style: TextStyle(color: AppTheme.hintTextColor),
                  ),
                );
              }

              final proofs = snapshot.data ?? [];
              return _buildProofListView(
                proofs: proofs.map((d) => _NormalisedProof.fromFirestore(d)).toList(),
                source: _ProofSource.firestore,
              );
            },
          );
        }

        // ── Drift fallback path (offline / permission-denied) ──────────────
        return dbAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor)),
          error: (e, _) => Center(
              child: Text('DB error: $e',
                  style: const TextStyle(color: AppTheme.errorColor))),
          data: (db) {
            // Cache Drift stream once — same reason as Firestore stream above.
            _driftStream ??= db.watchProofsForSession(widget.sessionId);
            return StreamBuilder<List<AttendanceProof>>(
              stream: _driftStream,
              builder: (context, snapshot) {
                final proofs = snapshot.data ?? [];
                return _buildProofListView(
                  proofs: proofs.map(_NormalisedProof.fromDrift).toList(),
                  source: _ProofSource.localBle,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProofListView({
    required List<_NormalisedProof> proofs,
    required _ProofSource source,
  }) {
    return Column(
      children: [
        // ── Source badge ───────────────────────────────────────────────────
        if (source == _ProofSource.localBle && _firestoreError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: AppTheme.cardColor,
            child: Row(
              children: [
                const Icon(Icons.bluetooth,
                    size: 14, color: AppTheme.secondaryTextColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _firestoreError!,
                    style: const TextStyle(
                        color: AppTheme.secondaryTextColor, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Retrying…',
                    style: TextStyle(
                        color: AppTheme.hintTextColor, fontSize: 10)),
              ],
            ),
          ),
        if (source == _ProofSource.firestore)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: AppTheme.cardColor,
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined,
                    size: 14, color: AppTheme.successColor),
                const SizedBox(width: 6),
                const Text(
                  'Live — cloud + BLE',
                  style: TextStyle(
                      color: AppTheme.successColor, fontSize: 11),
                ),
              ],
            ),
          ),

        // ── Proof list ─────────────────────────────────────────────────────
        Expanded(
          child: proofs.isEmpty
              ? Center(
                  child: Text(
                    source == _ProofSource.localBle
                        ? 'No students marked yet.\nStudents in BLE range will appear here.'
                        : 'No students marked yet.\nMake sure students have the app open.',
                    style: const TextStyle(
                        color: AppTheme.secondaryTextColor, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: proofs.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: AppTheme.inputBorderColor,
                    indent: 56,
                  ),
                  itemBuilder: (context, index) {
                    return _ProofTile(proof: proofs[index]);
                  },
                ),
        ),
      ],
    );
  }
}

// ── Normalised proof — unifies Firestore Map and Drift AttendanceProof ────────

class _NormalisedProof {
  const _NormalisedProof({
    required this.studentUid,
    required this.rssi,
    required this.timestamp,
    this.isLocal = false,
  });

  factory _NormalisedProof.fromFirestore(Map<String, dynamic> data) {
    DateTime ts;
    try {
      ts = (data['timestamp'] as dynamic).toDate() as DateTime;
    } catch (_) {
      ts = DateTime.now();
    }
    return _NormalisedProof(
      studentUid: data['studentUid'] as String? ?? '—',
      rssi: data['rssi'] as int? ?? 0,
      timestamp: ts,
    );
  }

  factory _NormalisedProof.fromDrift(AttendanceProof proof) {
    return _NormalisedProof(
      studentUid: proof.studentUid,
      rssi: proof.rssi,
      timestamp: proof.timestamp,
      isLocal: true,
    );
  }

  final String studentUid;
  final int rssi;
  final DateTime timestamp;
  /// True when the proof came from the local Drift DB (BLE ACK path).
  final bool isLocal;
}

// ── ProofTile — shows student name resolved from Firestore users collection ──────
//
// Accepts a _NormalisedProof (unified from Firestore or Drift).
// Name lookup: Firestore users/{studentUid} → 'name' field, UID fallback on error.
// Future is stored in initState to prevent name flicker on rebuild/scroll.

class _ProofTile extends StatefulWidget {
  const _ProofTile({required this.proof});

  final _NormalisedProof proof;

  @override
  State<_ProofTile> createState() => _ProofTileState();
}

class _ProofTileState extends State<_ProofTile> {
  late final Future<String> _nameFuture;

  @override
  void initState() {
    super.initState();
    _nameFuture = _fetchStudentName(widget.proof.studentUid);
  }

  Future<String> _fetchStudentName(String uid) async {
    if (uid.isEmpty || uid == '—') return '—';
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.fsUsers)
          .doc(uid)
          .get();
      final name = (doc.data()?['name'] as String?)?.trim() ?? '';
      return name.isNotEmpty ? name : uid;
    } catch (_) {
      return uid; // offline or permission error — show UID
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  bool _isUid(String value) => value.length >= 20 && !value.contains(' ');

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final rssi     = widget.proof.rssi;
    final rssiText = rssi == 0 ? 'GATT' : '$rssi dBm';
    final uidShort = widget.proof.studentUid.length > 16
        ? '${widget.proof.studentUid.substring(0, 16)}…'
        : widget.proof.studentUid;

    return FutureBuilder<String>(
      future: _nameFuture,
      builder: (context, snapshot) {
        final displayName  = snapshot.data ?? uidShort;
        final resolved     = snapshot.connectionState == ConnectionState.done;
        final showInitials = resolved && !_isUid(displayName);

        return Container(
          color: AppTheme.cardColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────────────────
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

              // ── Name + signal ─────────────────────────────────────────────
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
                      'Signal: $rssiText  ·  ${_formatTime(widget.proof.timestamp)}',
                      style: const TextStyle(
                          color: AppTheme.secondaryTextColor, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // ── Sync indicator ─────────────────────────────────────────────
              // Cloud icon when from Firestore, BLE icon when from local Drift.
              Icon(
                widget.proof.isLocal
                    ? Icons.bluetooth
                    : Icons.cloud_done_outlined,
                size: 18,
                color: widget.proof.isLocal
                    ? AppTheme.secondaryTextColor
                    : AppTheme.successColor,
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
