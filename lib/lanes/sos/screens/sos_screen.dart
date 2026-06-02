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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/providers.dart';
import '../sos_service.dart';
import '../widgets/sos_hold_button.dart';

// Convenience colors — mirror home_shell.dart AppShellColors
const _kRed = Color(0xFFEF4444);
const _kRedDim = Color(0x26EF4444); // 15% opacity
const _kSurface = Color(0xFF0F1923);
const _kCard = Color(0xFF1A2535);
const _kTextPrimary = Color(0xFFE2E8F0);
const _kTextSecondary = Color(0xFF8BA3C0);

// ── SosScreen ─────────────────────────────────────────────────────────────────

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  SosStatus _status = const SosStatus.idle();
  final List<IncomingSos> _incoming = [];

  @override
  void initState() {
    super.initState();
    _subscribeStreams();
  }

  void _subscribeStreams() {
    // We read the provider here imperatively because initState cannot use
    // ref.watch. The provider itself is watched in build() for rebuild on
    // service recreation (e.g. after logout/login).
    final sosAsync = ref.read(sosServiceProvider);
    sosAsync.whenData((svc) {
      svc.sosStatusStream.listen((s) {
        if (mounted) setState(() => _status = s);
      });
      svc.incomingSosStream.listen((inc) {
        if (mounted) {
          setState(() {
            _incoming.insert(0, inc);
            // Keep last 20 alerts in UI to avoid unbounded list
            if (_incoming.length > 20) _incoming.removeLast();
          });
        }
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

    final isActive = _status.type != SosStatusType.idle;
    final isGpsWarning = _status.type == SosStatusType.gpsWarning;
    final serviceError = sosAsync.hasError;

    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: serviceError
            ? _ServiceErrorView(error: sosAsync.error.toString())
            : Column(
                children: [
                  // ── Status banner ──────────────────────────────────────────
                  if (isActive) _ActiveBanner(status: _status),
                  if (isGpsWarning) _GpsWarningBanner(status: _status),

                  // ── Button area ────────────────────────────────────────────
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
                          const SizedBox(height: 24),
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

                  // ── Incoming alerts ────────────────────────────────────────
                  if (_incoming.isNotEmpty)
                    Expanded(
                      flex: 4,
                      child: _IncomingAlertList(alerts: _incoming),
                    )
                  else
                    const Expanded(
                      flex: 4,
                      child: _EmptyIncoming(),
                    ),
                ],
              ),
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

class _GpsWarningBanner extends StatelessWidget {
  const _GpsWarningBanner({required this.status});
  final SosStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      color: const Color(0xFF422006),
      child: Row(
        children: [
          const Icon(Icons.location_off, color: Color(0xFFFBBF24), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.message ?? 'GPS unavailable — no location attached',
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
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

class _IncomingAlertCard extends StatelessWidget {
  const _IncomingAlertCard({required this.alert});
  final IncomingSos alert;

  String _shortUid(String uid) =>
      uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;

  String _formatTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }

  bool get _hasLocation => alert.latitude != 0.0 || alert.longitude != 0.0;

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
                    Text(
                      'SOS from ${_shortUid(alert.senderUid)}',
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatTime(alert.timestamp),
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
                    '📍 ${alert.latitude.toStringAsFixed(5)}, '
                    '${alert.longitude.toStringAsFixed(5)}',
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

// ── Empty incoming state ──────────────────────────────────────────────────────

class _EmptyIncoming extends StatelessWidget {
  const _EmptyIncoming();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.sensors, color: Color(0xFF2D3F55), size: 36),
          SizedBox(height: 8),
          Text(
            'No SOS alerts received',
            style: TextStyle(color: Color(0xFF4D6480), fontSize: 13),
          ),
        ],
      ),
    );
  }
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
