import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../providers/ble_provider.dart';

// ── Tab definition ────────────────────────────────────────────────────────────

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.route,
    this.activeColor,
  });

  final String label;
  final IconData icon;
  final String route;
  final Color? activeColor; // override per-tab if needed (e.g. SOS red)
}

const List<_TabItem> _tabs = [
  _TabItem(
    label: 'Attendance',
    icon: Icons.check_circle_outline,
    route: '/home/attendance',
  ),
  _TabItem(
    label: 'Social',
    icon: Icons.chat_bubble_outline,
    route: '/home/social',
  ),
  _TabItem(
    label: 'SOS',
    icon: Icons.emergency,
    route: '/home/sos',
    activeColor: _AppShellColors.sos,
  ),
  _TabItem(
    label: 'Profile',
    icon: Icons.person_outline,
    route: '/home/profile',
  ),
];

// ── Shell screen ──────────────────────────────────────────────────────────────

/// Root shell used by GoRouter's [ShellRoute].
/// [child] is the currently active route's widget, injected by GoRouter.
class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen>
    with WidgetsBindingObserver {
  /// Derives the selected tab index from GoRouter's current location so the
  /// bottom bar stays in sync even when navigation happens programmatically
  /// (e.g. deep links, auth redirects).
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].route)) return i;
    }
    return 0; // default to Attendance
  }

  @override
  void initState() {
    super.initState();
    // Register as a WidgetsBindingObserver so didChangeAppLifecycleState fires
    // when the user returns from another app (e.g. camera for SOS photo).
    WidgetsBinding.instance.addObserver(this);
    // App always starts on Attendance tab after auth.
    // Set session duty cycle immediately so the student's phone is ready to
    // receive teacher attendance broadcasts from the first second.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyDutyCycleForTab(0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called whenever the app moves between foreground / background states.
  ///
  /// When the user returns to VEXT after using another app (camera, messages,
  /// etc.), the Dart timer driving the BLE duty cycle may have stalled while
  /// the main isolate was deprioritised by Android.
  ///
  /// On [AppLifecycleState.resumed] we call [setMode] on the transport layer,
  /// which cancels the stale timer and immediately starts a fresh scan cycle.
  /// This is cheap (no permission dialogs, no GATT setup) and guarantees that
  /// BLE is back at full speed within ~100ms of the user returning to the app.
  ///
  /// SOS mode is never downgraded here — if an SOS is active the transport
  /// layer is already in SOS duty cycle and [setMode] is idempotent.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final bleState = ref.read(bleStateProvider);
    if (!bleState.isActive) return; // BLE not started yet — nothing to restart.

    // Re-apply the effective mode via the lock-aware notifier. This cancels
    // the stalled duty-cycle timer and starts a fresh scan immediately.
    // The notifier's _applyEffectiveMode() re-evaluates all active locks and
    // the UI preference, so the correct mode is restored even if locks changed
    // while the app was backgrounded.
    ref.read(bleStateProvider.notifier)
        .setUiPreference(bleState.mode == MeshMode.idle
            ? MeshMode.idle
            : MeshMode.activeSession)
        .ignore();
    debugPrint('[Shell] App resumed — BLE duty cycle restarted '
        '(mode: ${bleState.mode})');
  }

  void _onTabTap(BuildContext context, int index) {
    final target = _tabs[index].route;
    final current = GoRouterState.of(context).uri.toString();

    // Avoid redundant navigation to the same route.
    if (!current.startsWith(target)) {
      context.go(target);
    }

    // Always update duty cycle on tab tap — idempotent and cheap.
    _applyDutyCycleForTab(index);
  }

  /// Set the UI preference for BLE duty cycle based on the active tab.
  ///
  /// This now uses the lock-aware [setUiPreference] API instead of calling
  /// startSession/startIdle directly. The key difference:
  ///
  ///   OLD: startSession() / startIdle() always applied the mode, overriding
  ///        any active service lock. Visiting Profile during attendance dropped
  ///        BLE to idle, breaking packet delivery for the entire class.
  ///
  ///   NEW: setUiPreference() only sets the BASE preference. The BleStateNotifier
  ///        lock system applies the effective mode = max(all active locks, pref).
  ///        If a session lock (teacher broadcasting) or SOS lock is held,
  ///        the BLE stays at session/SOS rate regardless of which tab is open.
  ///
  /// Tab mapping:
  ///   0 Attendance, 1 Social, 2 SOS → UI preference = activeSession
  ///   3 Profile                     → UI preference = idle
  ///
  /// Profile preference WILL take effect when no service locks are held (no
  /// active session, no SOS). This is the only correct time to drop to idle.
  void _applyDutyCycleForTab(int index) {
    final notifier = ref.read(bleStateProvider.notifier);
    final isActiveLane = index < 3;

    if (isActiveLane) {
      notifier.setUiPreference(MeshMode.activeSession).ignore();
    } else {
      // Profile: prefer idle, but service locks will override if needed.
      notifier.setUiPreference(MeshMode.idle).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    // Watch BLE connection state — replace bleActiveProvider with your actual
    // provider. It should expose a bool (true = BLE active / connected).
    final isBleActive = ref.watch(bleActiveProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: _AppShellColors.navyBackground,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black26,
        centerTitle: false,
        title: const Text(
          'VEXT',
          style: TextStyle(
            color: _AppShellColors.navyTitle,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 5,
            shadows: [
              Shadow(color: Color(0x5506B6D4), blurRadius: 14),
              Shadow(color: Color(0x2822D3EE), blurRadius: 28),
            ],
          ),
        ),
        actions: [
          _BleStatusIndicator(isActive: isBleActive),
          const SizedBox(width: 16),
        ],
      ),

      // ── Body (GoRouter child) ───────────────────────────────────────────
      body: widget.child,

      // ── Bottom Navigation ───────────────────────────────────────────────
      bottomNavigationBar: _AppBottomNavBar(
        currentIndex: currentIndex,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}

// ── Bottom nav bar ────────────────────────────────────────────────────────────

class _AppBottomNavBar extends StatelessWidget {
  const _AppBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _AppShellColors.navBackground,
        border: Border(
          top: BorderSide(color: _AppShellColors.navBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_tabs.length, (index) {
              return Expanded(
                child: _NavBarItem(
                  tab: _tabs[index],
                  isSelected: currentIndex == index,
                  onTap: () => onTap(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ── Single nav item ───────────────────────────────────────────────────────────

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final _TabItem tab;
  final bool isSelected;
  final VoidCallback onTap;

  bool get _isSos => tab.route == '/home/sos';

  Color _resolveActiveColor() =>
      tab.activeColor ?? _AppShellColors.selectedItem;

  @override
  Widget build(BuildContext context) {
    final activeColor = _resolveActiveColor();
    final inactiveColor = _isSos
        ? _AppShellColors.sosInactive
        : _AppShellColors.unselectedItem;

    final iconColor = isSelected ? activeColor : inactiveColor;
    final labelColor = isSelected ? activeColor : _AppShellColors.unselectedItem;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // SOS gets a pill/badge treatment to make it stand out
          if (_isSos) ...[
            _SosBadge(isSelected: isSelected),
          ] else ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                tab.icon,
                key: ValueKey(isSelected),
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: labelColor,
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.2,
              ),
              child: Text(tab.label),
            ),
          ],
        ],
      ),
    );
  }
}

// ── SOS badge ─────────────────────────────────────────────────────────────────

/// The SOS tab renders as a compact pill with a red background to visually
/// separate it from the standard tabs.
class _SosBadge extends StatelessWidget {
  const _SosBadge({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? _AppShellColors.sos
            : _AppShellColors.sos.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: _AppShellColors.sos.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emergency,
            size: 16,
            color: isSelected ? Colors.white : _AppShellColors.sos,
          ),
          const SizedBox(width: 5),
          Text(
            'SOS',
            style: TextStyle(
              color: isSelected ? Colors.white : _AppShellColors.sos,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── BLE status indicator ──────────────────────────────────────────────────────

class _BleStatusIndicator extends StatelessWidget {
  const _BleStatusIndicator({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final dotColor =
        isActive ? _AppShellColors.bleActive : _AppShellColors.bleInactive;
    final label = isActive ? 'MESH ON' : 'MESH OFF';
    final labelColor = isActive
        ? _AppShellColors.bleActive
        : _AppShellColors.bleInactiveLabel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive
            ? _AppShellColors.bleActive.withValues(alpha: 0.10)
            : _AppShellColors.bleInactive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dotColor.withValues(alpha: isActive ? 0.35 : 0.20),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing dot when active, static when not
          isActive
              ? _PulsingDot(color: dotColor)
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing dot animation ─────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
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
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.25 * _pulse.value),
            ),
          ),
          // Inner solid dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Color tokens ──────────────────────────────────────────────────────────────

abstract class _AppShellColors {
  // AppBar
  static const Color navyBackground = Color(0xFF0A1520); // matches surfaceColor
  static const Color navyTitle = Color(0xFF22D3EE); // signal cyan accent

  // Bottom nav
  static const Color navBackground = Color(0xFF0C1828);
  static const Color navBorder = Color(0xFF0D2646);
  static const Color selectedItem = Color(0xFF22D3EE); // signal cyan
  static const Color unselectedItem = Color(0xFF3C5870);

  // SOS
  static const Color sos = Color(0xFFFF3B30); // Apple emergency red
  static const Color sosInactive = Color(0xFFFF3B30); // red even when inactive

  // BLE / Mesh
  static const Color bleActive = Color(0xFF10D979); // electric mesh-green
  static const Color bleInactive = Color(0xFF374060);
  static const Color bleInactiveLabel = Color(0xFF4A6280);
}
