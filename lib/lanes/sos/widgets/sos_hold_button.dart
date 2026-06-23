// ── SosHoldButton — VEXT Lane C ───────────────────────────────────────────────
//
// A 3-second animated press-and-hold button that prevents accidental SOS triggers.
//
// Behaviour:
//   • User presses and holds — a ring fills clockwise over 3 seconds.
//   • Releasing before 3 s → ring springs back, no action taken.
//   • Holding for 3 s → ring completes, [onTriggered] is called once.
//   • While [isActive] is true the button switches to a pulsing red "CANCEL"
//     state so the user can stop the re-broadcast.
//
// Animation contract:
//   • Ring uses AnimationController(vsync, duration: 3s)
//   • GestureDetector.onLongPressStart → controller.forward()
//   • GestureDetector.onLongPressEnd / onLongPressCancel → controller.reverse()
//   • AnimationStatus.completed → onTriggered()
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── SosHoldButton ─────────────────────────────────────────────────────────────

class SosHoldButton extends StatefulWidget {
  const SosHoldButton({
    super.key,
    required this.onTriggered,
    required this.onCancel,
    required this.isActive,
    this.size = 160.0,
  });

  /// Called once when the 3-second hold completes.
  final VoidCallback onTriggered;

  /// Called when the user taps CANCEL while SOS is active.
  final VoidCallback onCancel;

  /// True while an SOS is in progress — switches button to cancel mode.
  final bool isActive;

  /// Diameter of the button circle in logical pixels.
  final double size;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final AnimationController _pulseController;
  late final AnimationController _rippleController;
  late final Animation<double> _pulseAnim;
  bool _triggered = false;

  static const Color _red = Color(0xFFFF3B30); // Apple emergency red
  static const Color _darkRed = Color(0xFFCC1500); // pressed/shadow shade
  static const Color _bgRing = Color(0xFF0F1D30); // matches new cardColor

  @override
  void initState() {
    super.initState();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener(_onRingStatus);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 2400ms ripple cycle — 3 rings staggered at 1/3 offsets each.
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didUpdateWidget(SosHoldButton old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _pulseController.repeat(reverse: true);
      _rippleController.repeat();
    } else if (!widget.isActive && old.isActive) {
      _pulseController.stop();
      _pulseController.value = 0;
      _rippleController.stop();
      _rippleController.reset();
      _triggered = false;
    }
  }

  void _onRingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_triggered) {
      _triggered = true;
      widget.onTriggered();
    }
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (widget.isActive) return;
    _triggered = false;
    _ringController.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_triggered) _ringController.reverse();
  }

  void _onLongPressCancel() {
    if (!_triggered) _ringController.reverse();
  }

  @override
  void dispose() {
    _ringController.dispose();
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  /// Builds a single expanding ripple ring.
  /// [t] is 0.0 (just appeared at button surface) → 1.0 (fully expanded + gone).
  Widget _buildRippleRing(double baseSize, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final ringSize = baseSize * (1.0 + clampedT * 0.85);
    final opacity = (1.0 - clampedT) * 0.45;
    if (opacity < 0.01) return const SizedBox.shrink();
    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _red.withValues(alpha: opacity),
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    if (widget.isActive) {
      // ── Cancel mode — pulsing red button with expanding ripple rings ───────
      return AnimatedBuilder(
        animation: _rippleController,
        builder: (context, child) {
          final v = _rippleController.value;
          return SizedBox(
            // Extra space so ripple rings don't get clipped
            width: size * 2.0,
            height: size * 2.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 3 staggered rings — offset by 1/3 of the cycle each
                _buildRippleRing(size, v),
                _buildRippleRing(size, (v + 0.333) % 1.0),
                _buildRippleRing(size, (v + 0.666) % 1.0),
                // The cancel button itself
                child!,
              ],
            ),
          );
        },
        child: ScaleTransition(
          scale: _pulseAnim,
          child: GestureDetector(
            onTap: widget.onCancel,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _red,
                boxShadow: [
                  BoxShadow(
                    color: _red.withValues(alpha: 0.55),
                    blurRadius: 28,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close, color: Colors.white, size: 32),
                  SizedBox(height: 4),
                  Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Idle mode — press-and-hold ring ────────────────────────────────────
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: AnimatedBuilder(
        animation: _ringController,
        builder: (context, _) {
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _bgRing,
                  ),
                ),
                // Progress ring
                CustomPaint(
                  size: Size(size, size),
                  painter: _RingPainter(
                    progress: _ringController.value,
                    color: _red,
                    trackColor: const Color(0xFF374151),
                    strokeWidth: 6,
                  ),
                ),
                // Inner button
                Container(
                  width: size - 20,
                  height: size - 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ringController.value > 0
                        ? Color.lerp(const Color(0xFF1F2937), _darkRed,
                            _ringController.value)
                        : const Color(0xFF1F2937),
                    boxShadow: _ringController.value > 0
                        ? [
                            BoxShadow(
                              color: _red.withValues(
                                  alpha: _ringController.value * 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.emergency,
                        color: Color.lerp(
                            const Color(0xFF9CA3AF), _red, _ringController.value),
                        size: 36,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SOS',
                        style: TextStyle(
                          color: Color.lerp(
                              const Color(0xFF9CA3AF), Colors.white,
                              _ringController.value),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Ring painter ───────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -math.pi / 2; // 12 o'clock

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0) {
      // Progress arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
