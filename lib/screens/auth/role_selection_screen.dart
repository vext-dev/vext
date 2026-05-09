import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_service_provider.dart'; // adjust to your project structure
import '../theme/app_theme.dart'; // adjust to your project structure

enum UserRole { student, teacher, security }

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.student:
        return 'Student';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.security:
        return 'Security';
    }
  }

  String get description {
    switch (this) {
      case UserRole.student:
        return 'Access courses, schedules & campus resources';
      case UserRole.teacher:
        return 'Manage classes, attendance & student records';
      case UserRole.security:
        return 'Monitor access, incidents & safety reports';
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.student:
        return Icons.school;
      case UserRole.teacher:
        return Icons.person;
      case UserRole.security:
        return Icons.security;
    }
  }

  String get value => label.toLowerCase();
}

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  UserRole? _selectedRole;
  UserRole? _loadingRole; // tracks which card is mid-request

  Future<void> _handleRoleSelect(UserRole role) async {
    if (_loadingRole != null) return; // prevent concurrent taps

    setState(() {
      _selectedRole = role;
      _loadingRole = role;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.setUserRole(role.value);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedRole = null;
          _loadingRole = null;
        });
        _showErrorSnackBar(_friendlyError(e));
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('connection')) {
      return 'Network error. Please check your connection.';
    } else if (message.contains('permission') ||
        message.contains('unauthorized')) {
      return 'Permission denied. Please sign in again.';
    }
    return 'Could not set role. Please try again.';
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _RoleTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),

              // ── Logo ──────────────────────────────────────────────────
              Text(
                'VEXT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _RoleTheme.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 40),

              // ── Title ─────────────────────────────────────────────────
              Text(
                'Select Your Role',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: _RoleTheme.title,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),

              // ── Subtitle ──────────────────────────────────────────────
              Text(
                'This determines your app features and permissions',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _RoleTheme.subtitle,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),

              // ── Role Cards ────────────────────────────────────────────
              Expanded(
                child: Column(
                  children: UserRole.values.map((role) {
                    final isSelected = _selectedRole == role;
                    final isLoading = _loadingRole == role;
                    final isDisabled =
                        _loadingRole != null && _loadingRole != role;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _RoleCard(
                          role: role,
                          isSelected: isSelected,
                          isLoading: isLoading,
                          isDisabled: isDisabled,
                          onTap: isDisabled
                              ? null
                              : () => _handleRoleSelect(role),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Role Card ─────────────────────────────────────────────────────────────────

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.role,
    required this.isSelected,
    required this.isLoading,
    required this.isDisabled,
    required this.onTap,
  });

  final UserRole role;
  final bool isSelected;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.isDisabled) _pressController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _pressController.reverse();
  }

  void _onTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || widget.isLoading;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isActive ? _RoleTheme.cardActiveBackground : _RoleTheme.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? _RoleTheme.accent : _RoleTheme.cardBorder,
              width: isActive ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isActive
                    ? _RoleTheme.accent.withOpacity(0.18)
                    : _RoleTheme.shadow,
                blurRadius: isActive ? 20 : 12,
                offset: const Offset(0, 4),
                spreadRadius: isActive ? 1 : 0,
              ),
            ],
          ),
          child: Opacity(
            opacity: widget.isDisabled ? 0.45 : 1.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Row(
                children: [
                  // Icon container
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isActive
                          ? _RoleTheme.accent
                          : _RoleTheme.iconBackground,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: widget.isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: isActive
                                  ? Colors.white
                                  : _RoleTheme.accent,
                            ),
                          )
                        : Icon(
                            widget.role.icon,
                            size: 30,
                            color: isActive
                                ? Colors.white
                                : _RoleTheme.iconColor,
                          ),
                  ),
                  const SizedBox(width: 20),

                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.role.label,
                          style: TextStyle(
                            color: isActive
                                ? _RoleTheme.accent
                                : _RoleTheme.title,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.role.description,
                          style: TextStyle(
                            color: _RoleTheme.subtitle,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Chevron / check
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isActive
                        ? Icon(
                            Icons.check_circle_rounded,
                            key: const ValueKey('check'),
                            color: _RoleTheme.accent,
                            size: 24,
                          )
                        : Icon(
                            Icons.chevron_right_rounded,
                            key: const ValueKey('chevron'),
                            color: _RoleTheme.subtitle,
                            size: 24,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Theme tokens ──────────────────────────────────────────────────────────────

abstract class _RoleTheme {
  // Backgrounds
  static const Color background = Color(0xFF0D1B2A);
  static const Color cardBackground = Color(0xFF132338);
  static const Color cardActiveBackground = Color(0xFF162D47);
  static const Color iconBackground = Color(0xFF1C3250);

  // Navy/blue accent
  static const Color accent = Color(0xFF3B82F6);

  // Text
  static const Color title = Color(0xFFE8EEF6);
  static const Color subtitle = Color(0xFF7A94B0);

  // Borders & shadow
  static const Color cardBorder = Color(0xFF1E3A56);
  static Color get shadow => const Color(0xFF000000).withOpacity(0.25);

  // Icon
  static const Color iconColor = Color(0xFF3B82F6);
}
