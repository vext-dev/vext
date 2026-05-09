import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/ble_provider.dart'; // adjust to your project structure
import '../theme/app_theme.dart'; // adjust to your project structure

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

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
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

  void _onTabTap(BuildContext context, int index) {
    final target = _tabs[index].route;
    final current = GoRouterState.of(context).uri.toString();

    // Avoid redundant navigation to the same route
    if (!current.startsWith(target)) {
      context.go(target);
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
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
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
            : _AppShellColors.sos.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: _AppShellColors.sos.withOpacity(0.35),
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
    final dotColor = isActive
        ? _AppShellColors.bleActive
        : _AppShellColors.bleInactive;

    final label = isActive ? 'BLE On' : 'BLE Off';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing dot when active
        isActive
            ? _PulsingDot(color: dotColor)
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: isActive
                ? _AppShellColors.bleActive
                : _AppShellColors.bleInactiveLabel,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
              color: widget.color.withOpacity(0.25 * _pulse.value),
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
  static const Color navyBackground = Color(0xFF0D1B2A);
  static const Color navyTitle = Color(0xFF3B82F6); // sky blue

  // Bottom nav
  static const Color navBackground = Color(0xFF0F2035);
  static const Color navBorder = Color(0xFF1A3352);
  static const Color selectedItem = Color(0xFF38BDF8); // sky blue
  static const Color unselectedItem = Color(0xFF4D7096);

  // SOS
  static const Color sos = Color(0xFFEF4444);
  static const Color sosInactive = Color(0xFFEF4444); // red even when inactive

  // BLE
  static const Color bleActive = Color(0xFF22C55E); // green
  static const Color bleInactive = Color(0xFF4B5563); // grey
  static const Color bleInactiveLabel = Color(0xFF6B7280);
}
