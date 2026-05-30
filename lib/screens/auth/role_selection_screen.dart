import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_service_provider.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  bool _isLoading = false;
  String? _selectedRole; // tracks which card is being pressed

  static const _roles = [
    _RoleDef(
      id: 'student',
      title: 'Student',
      subtitle: 'Auto attendance via BLE mesh. Receive SOS alerts from peers.',
      icon: Icons.school_outlined,
    ),
    _RoleDef(
      id: 'teacher',
      title: 'Teacher',
      subtitle: 'Start attendance sessions. Broadcast presence to students in range.',
      icon: Icons.cast_for_education_outlined,
    ),
    _RoleDef(
      id: 'security',
      title: 'Security',
      subtitle: 'Receive all SOS broadcasts. Monitor campus alerts in real time.',
      icon: Icons.security_outlined,
    ),
  ];

  Future<void> _selectRole(String roleId) async {
    if (_isLoading) return;

    final authAsync = ref.read(authStateProvider);
    final user = authAsync.valueOrNull;
    if (user == null) {
      _showError('Session expired. Please log in again.');
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    setState(() {
      _isLoading = true;
      _selectedRole = roleId;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.updateRole(user.uid, roleId);
      if (mounted) context.go(AppRoutes.attendance);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedRole = null;
        });
        _showError(_friendlyError(e));
      }
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Please check your connection.';
    }
    if (msg.contains('permission') || msg.contains('denied')) {
      return 'Permission denied. Please sign in again.';
    }
    return 'Could not save your role. Please try again.';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              const Text(
                'VEXT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 48),

              // Headline
              const Text(
                'Choose your role',
                style: TextStyle(
                  color: AppTheme.primaryTextColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This determines your features and permissions in the mesh network.',
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // Role cards
              Expanded(
                child: Column(
                  children: _roles
                      .map((role) => _RoleCard(
                            role: role,
                            isLoading:
                                _isLoading && _selectedRole == role.id,
                            isDisabled:
                                _isLoading && _selectedRole != role.id,
                            onTap: () => _selectRole(role.id),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Role definition ────────────────────────────────────────────────────────────

class _RoleDef {
  const _RoleDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

// ── Role card widget ──────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.onTap,
    required this.isLoading,
    required this.isDisabled,
  });

  final _RoleDef role;
  final VoidCallback onTap;
  final bool isLoading;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AnimatedOpacity(
        opacity: isDisabled ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: isDisabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.inputBorderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : Icon(role.icon,
                          color: AppTheme.primaryColor, size: 26),
                ),
                const SizedBox(width: 16),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.title,
                        style: const TextStyle(
                          color: AppTheme.primaryTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role.subtitle,
                        style: const TextStyle(
                          color: AppTheme.secondaryTextColor,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Arrow
                if (!isLoading)
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppTheme.secondaryTextColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
