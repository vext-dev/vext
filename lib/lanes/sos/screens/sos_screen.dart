// ── SosScreen — VEXT Lane C SOS Emergency ─────────────────────────────────────
//
// Single screen that adapts to the user's role and SOS state:
//
//   Idle (any role):
//     • "Hold 3 seconds to send SOS" instruction
//     • SosHoldButton centered on screen
//     • Incoming SOS alerts list (visible to all roles but prominent for security)
//
//   Active (originator):
//     • "SOS SENT — Relaying…" status bar with pulsing red indicator
//     • SosHoldButton in cancel mode (shows CANCEL)
//     • Last known GPS coordinates if available
//
//   Incoming SOS card (security / all):
//     • Animated alert card per incoming SOS with sender UID, timestamp,
//       and GPS coordinates (if non-zero)
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_constants.dart';
import '../../../providers/providers.dart';
import '../sos_service.dart';
import '../widgets/sos_hold_button.dart';

// Convenience colors — keep in sync with AppTheme + _AppShellColors
const _kRed = Color(0xFFFF3B30); // Apple emergency red
const _kRedDim = Color(0x26FF3B30); // 15% opacity
const _kSurface = Color(0xFF060E1A); // matches AppTheme.backgroundColor
const _kCard = Color(0xFF0F1D30); // matches AppTheme.cardColor
const _kTextPrimary = Color(0xFFEDF4FF); // matches AppTheme.primaryTextColor
const _kTextSecondary = Color(0xFF7EA8C8); // matches AppTheme.secondaryTextColor

// ── SosScreen ─────────────────────────────────────────────────────────────────

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  SosStatus _status = const SosStatus.idle();

  // Stored so it can be cancelled in dispose() — prevents memory leaks and
  // duplicate setState calls if the widget is somehow recreated.
  StreamSubscription<SosStatus>? _statusSub;

  // NOTE: incoming SOS alerts are NO LONGER stored here.
  // They live in incomingSosProvider (StateNotifierProvider) so alerts
  // received while this tab is not open are never lost.
  // See: lib/providers/sos_service_provider.dart → IncomingSosNotifier.

  @override
  void initState() {
    super.initState();
    // TWO-PART subscription strategy (avoids fireImmediately which is not
    // universally supported across Riverpod 2.x patch versions):
    //
    // Part 1 — handled here (initState + addPostFrameCallback):
    //   Covers the case where sosServiceProvider is ALREADY resolved when
    //   the screen first builds. addPostFrameCallback fires after the first
    //   frame, at which point ref.read gives the current value. If the service
    //   is already AsyncData we subscribe immediately.
    //
    // Part 2 — handled in build() via ref.listen (no fireImmediately):
    //   Covers the case where the service resolves AFTER the first build
    //   (still loading) or is recreated after logout/login. ref.listen fires
    //   on every provider value change, so both transitions are caught.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscribeToStatusStream(ref.read(sosServiceProvider));
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  /// Subscribe to [sosAsync]'s status stream if it is resolved.
  /// Cancels any existing subscription first (idempotent, safe to call
  /// multiple times — e.g. from both initState and ref.listen).
  void _subscribeToStatusStream(AsyncValue<SosService> sosAsync) {
    sosAsync.whenData((svc) {
      _statusSub?.cancel();
      _statusSub = svc.sosStatusStream.listen((s) {
        if (mounted) setState(() => _status = s);
      });
    });
  }

  Future<void> _onTriggered() async {
    final svc = ref.read(sosServiceProvider).valueOrNull;
    if (svc == null) return;
    await svc.triggerSos();
  }

  Future<void> _onCancel() async {
    final svc = ref.read(sosServiceProvider).valueOrNull;
    if (svc == null) return;
    await svc.cancelSos();
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the screen rebuilds if the service is recreated.
    final sosAsync = ref.watch(sosServiceProvider);

    // Part 2 of the two-part subscription strategy (see initState for Part 1).
    // Fires when sosServiceProvider transitions from loading → data, or when
    // the service is recreated after logout/login.
    // Does NOT need fireImmediately — Part 1 (initState) covers the case where
    // the service is already resolved at first build.
    ref.listen<AsyncValue<SosService>>(
      sosServiceProvider,
      (_, next) => _subscribeToStatusStream(next),
    );

    // Incoming alerts from the provider — persists across tab switches.
    final incoming = ref.watch(incomingSosProvider);

    // isActive: SOS is transmitting (covers both 'active' and 'gpsWarning').
    // isGpsWarning: SOS active but GPS was unavailable — show the GPS banner
    //   INSTEAD OF (not in addition to) the standard active banner, since the
    //   GPS banner already communicates that SOS is in progress.
    final isActive = _status.type != SosStatusType.idle;
    final isGpsWarning = _status.type == SosStatusType.gpsWarning;
    final serviceError = sosAsync.hasError;

    return Scaffold(
      backgroundColor: _kSurface,
      body: Stack(
        children: [
          // ── Active SOS radial red overlay ──────────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 700),
                opacity: isActive ? 1.0 : 0.0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, -0.25),
                      radius: 1.1,
                      colors: [
                        Color(0x22FF3B30),
                        Color(0x00FF3B30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────────
          SafeArea(
            child: serviceError
                ? _ServiceErrorView(error: sosAsync.error.toString())
                : Column(
                    children: [
                      // ── Status banner ──────────────────────────────────────
                      // Show GPS warning banner when GPS is unavailable — it
                      // already communicates SOS is active, so the standard
                      // active banner is suppressed to avoid double-stacking.
                      // Show standard active banner only when GPS succeeded.
                      if (isGpsWarning)
                        _GpsWarningBanner(status: _status)
                      else if (isActive)
                        _ActiveBanner(status: _status),

                      // ── Button area ────────────────────────────────────────
                      Expanded(
                        flex: 5,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SosHoldButton(
                                onTriggered: _onTriggered,
                                onCancel: _onCancel,
                                isActive: isActive,
                              ),
                              const SizedBox(height: 28),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: isActive
                                    ? const _RelayingIndicator()
                                    : const _HoldInstruction(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Section divider ────────────────────────────────────
                      _AlertsSectionHeader(hasAlerts: incoming.isNotEmpty),

                      // ── Incoming alerts ────────────────────────────────────
                      if (incoming.isNotEmpty)
                        Expanded(
                          flex: 4,
                          child: _IncomingAlertList(alerts: incoming),
                        )
                      else
                        const Expanded(
                          flex: 4,
                          child: _EmptyIncoming(),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Active status banner ───────────────────────────────────────────────────────

class _ActiveBanner extends StatefulWidget {
  const _ActiveBanner({required this.status});
  final SosStatus status;

  @override
  State<_ActiveBanner> createState() => _ActiveBannerState();
}

class _ActiveBannerState extends State<_ActiveBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      color: _kRedDim,
      child: Row(
        children: [
          FadeTransition(
            opacity: _pulse,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kRed,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'SOS ACTIVE — RELAYING ON MESH',
              style: const TextStyle(
                color: _kRed,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── GPS warning banner ────────────────────────────────────────────────────────

// GPS warning banner — shown INSTEAD of _ActiveBanner when GPS was unavailable.
// It communicates both "SOS is active" (red left border + pulsing dot inherited
// from _ActiveBanner's design language) AND "GPS unavailable" (amber warning row)
// in a single banner so the user is not overwhelmed by two stacked banners.
class _GpsWarningBanner extends StatefulWidget {
  const _GpsWarningBanner({required this.status});
  final SosStatus status;

  @override
  State<_GpsWarningBanner> createState() => _GpsWarningBannerState();
}

class _GpsWarningBannerState extends State<_GpsWarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // SOS-active row (same as _ActiveBanner)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          color: _kRedDim,
          child: Row(
            children: [
              FadeTransition(
                opacity: _pulse,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kRed,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'SOS ACTIVE — RELAYING ON MESH',
                  style: TextStyle(
                    color: _kRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // GPS warning row below
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 20),
          color: const Color(0xFF422006),
          child: Row(
            children: [
              const Icon(Icons.location_off, color: Color(0xFFFBBF24), size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.status.message ?? 'GPS unavailable — no location attached',
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Hold instruction text ─────────────────────────────────────────────────────

class _HoldInstruction extends StatelessWidget {
  const _HoldInstruction();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text(
          'Hold 3 seconds to send SOS',
          style: TextStyle(
            color: _kTextSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Emergency alert will broadcast to all nearby devices',
          style: TextStyle(
            color: Color(0xFF4D6480),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Relaying indicator ────────────────────────────────────────────────────────

class _RelayingIndicator extends StatelessWidget {
  const _RelayingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text(
          'SOS SENT — Relaying…',
          style: TextStyle(
            color: _kRed,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Tap CANCEL to stop re-broadcasting',
          style: TextStyle(
            color: _kTextSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ── Incoming alerts ───────────────────────────────────────────────────────────

class _IncomingAlertList extends StatelessWidget {
  const _IncomingAlertList({required this.alerts});
  final List<IncomingSos> alerts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            'INCOMING SOS ALERTS',
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: alerts.length,
            itemBuilder: (context, i) => _IncomingAlertCard(alert: alerts[i]),
          ),
        ),
      ],
    );
  }
}

// Converted to StatefulWidget so the Firestore name lookup runs once per card
// (same pattern as _ProofTile and _MessageBubble). Avoids refiring on rebuild.
class _IncomingAlertCard extends StatefulWidget {
  const _IncomingAlertCard({required this.alert});
  final IncomingSos alert;

  @override
  State<_IncomingAlertCard> createState() => _IncomingAlertCardState();
}

class _IncomingAlertCardState extends State<_IncomingAlertCard> {
  late final Future<String> _nameFuture;

  @override
  void initState() {
    super.initState();
    _nameFuture = _fetchSenderName(widget.alert.senderUid);
  }

  Future<String> _fetchSenderName(String uid) async {
    if (uid.isEmpty) return 'Unknown';
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.fsUsers)
          .doc(uid)
          .get();
      final name = (doc.data()?['name'] as String?)?.trim() ?? '';
      return name.isNotEmpty ? name : _shortUid(uid);
    } catch (_) {
      return _shortUid(uid);
    }
  }

  String _shortUid(String uid) =>
      uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;

  String _formatTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }

  bool get _hasLocation =>
      widget.alert.latitude != 0.0 || widget.alert.longitude != 0.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kRed.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kRedDim,
              border: Border.all(color: _kRed, width: 1.5),
            ),
            child: const Icon(Icons.emergency, color: _kRed, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Name resolved from Firestore; falls back to short UID
                    FutureBuilder<String>(
                      future: _nameFuture,
                      builder: (context, snapshot) {
                        final name = snapshot.data ??
                            _shortUid(widget.alert.senderUid);
                        return Text(
                          'SOS from $name',
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                    Text(
                      _formatTime(widget.alert.timestamp),
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_hasLocation)
                  Text(
                    '📍 ${widget.alert.latitude.toStringAsFixed(5)}, '
                    '${widget.alert.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 12,
                    ),
                  )
                else
                  const Text(
                    '📍 Location unavailable',
                    style: TextStyle(
                      color: Color(0xFF4D6480),
                      fontSize: 12,
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

// ── Alerts section header ─────────────────────────────────────────────────────

class _AlertsSectionHeader extends StatelessWidget {
  const _AlertsSectionHeader({required this.hasAlerts});
  final bool hasAlerts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: _kRed.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          const Text(
            'INCOMING ALERTS',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: const Color(0xFF1A2D42)),
          ),
          if (hasAlerts) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kRed.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: _kRed,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Empty incoming state — animated radar ────────────────────────────────────

class _EmptyIncoming extends StatefulWidget {
  const _EmptyIncoming();

  @override
  State<_EmptyIncoming> createState() => _EmptyIncomingState();
}

class _EmptyIncomingState extends State<_EmptyIncoming>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated radar ping
          SizedBox(
            width: 64,
            height: 64,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) =>
                  CustomPaint(painter: _RadarPainter(_anim.value)),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'SCANNING MESH',
            style: TextStyle(
              color: Color(0xFF2A4A6B),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'No SOS alerts received',
            style: TextStyle(color: Color(0xFF4D6480), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Radar painter ─────────────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.progress);

  final double progress; // 0.0 → 1.0

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Static outer ring
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..color = const Color(0xFF1A3352)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Inner static ring
    canvas.drawCircle(
      center,
      maxRadius * 0.55,
      Paint()
        ..color = const Color(0xFF1A3352).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Center node
    canvas.drawCircle(
      center,
      3.5,
      Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.70),
    );

    // Cross-hairs
    final crossPaint = Paint()
      ..color = const Color(0xFF1E3352)
      ..strokeWidth = 0.7;
    canvas.drawLine(
        Offset(center.dx, center.dy - maxRadius),
        Offset(center.dx, center.dy + maxRadius),
        crossPaint);
    canvas.drawLine(
        Offset(center.dx - maxRadius, center.dy),
        Offset(center.dx + maxRadius, center.dy),
        crossPaint);

    // Expanding ping ring
    final pingRadius = maxRadius * progress;
    final pingOpacity = (1.0 - progress) * 0.65;
    if (pingOpacity > 0.01) {
      canvas.drawCircle(
        center,
        pingRadius,
        Paint()
          ..color = const Color(0xFF3B82F6).withValues(alpha: pingOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

// ── Service error fallback ────────────────────────────────────────────────────

class _ServiceErrorView extends StatelessWidget {
  const _ServiceErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _kRed, size: 48),
            const SizedBox(height: 16),
            const Text(
              'SOS unavailable',
              style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
