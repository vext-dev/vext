import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart'; // retained for context.push(AppRoutes.test) in _MeshTestButton

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_service_provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/crypto_service_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: authAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
          error: (e, _) => Center(
            child: Text('Error: $e', style: const TextStyle(color: AppTheme.errorColor)),
          ),
          data: (user) => _ProfileBody(
            displayName: user?.displayName ?? '',
            email: user?.email ?? '',
            role: user?.role ?? 'student',
            uid: user?.uid ?? '',
          ),
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.displayName,
    required this.email,
    required this.role,
    required this.uid,
  });

  final String displayName;
  final String email;
  final String role;
  final String uid;

  String get _initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBleActive = ref.watch(bleActiveProvider);
    final bleMode = ref.watch(bleStateProvider).mode;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Avatar + name ───────────────────────────────────────────────
          Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                displayName.isNotEmpty ? displayName : 'User',
                style: const TextStyle(
                  color: AppTheme.primaryTextColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Account card ────────────────────────────────────────────────
          _SectionCard(
            title: 'Account',
            children: [
              _InfoRow(
                icon: Icons.person_outline,
                label: 'Name',
                value: displayName.isNotEmpty ? displayName : '—',
              ),
              _Divider(),
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: email,
              ),
              _Divider(),
              _InfoRow(
                icon: Icons.badge_outlined,
                label: 'Role',
                valueWidget: _RoleBadge(role: role),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Connectivity card ───────────────────────────────────────────
          _SectionCard(
            title: 'Connectivity',
            children: [
              _InfoRow(
                icon: Icons.bluetooth,
                label: 'BLE Status',
                valueWidget: _BleStatusChip(isActive: isBleActive),
              ),
              _Divider(),
              _InfoRow(
                icon: Icons.radar,
                label: 'Mesh Mode',
                value: bleMode.name[0].toUpperCase() + bleMode.name.substring(1),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Device identity card ────────────────────────────────────────
          _SectionCard(
            title: 'Device Identity',
            children: [
              _InfoRow(
                icon: Icons.fingerprint,
                label: 'Node Fingerprint',
                valueWidget: _FingerprintChip(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Sign out ────────────────────────────────────────────────────
          _SignOutButton(),
          const SizedBox(height: 16),

          // ── Developer: Mesh Test Screen ─────────────────────────────────
          // TODO: remove this button after Milestone 3 two-phone test is signed off.
          _MeshTestButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Node fingerprint chip ─────────────────────────────────────────────────────

/// Shows the 16-hex-char node fingerprint derived from the X25519 public key.
/// CryptoService.initialize() is called once at app start via
/// cryptoServiceProvider — by the time the Profile screen is visible the
/// future is resolved.
class _FingerprintChip extends ConsumerWidget {
  const _FingerprintChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cryptoAsync = ref.watch(cryptoServiceProvider);

    return cryptoAsync.when(
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.primaryColor,
        ),
      ),
      error: (_, __) => const Text(
        'Key error',
        style: TextStyle(color: AppTheme.errorColor, fontSize: 11),
      ),
      data: (crypto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          crypto.fingerprint,
          style: const TextStyle(
            color: AppTheme.primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ── Mesh test screen button (debug only) ──────────────────────────────────────

/// Developer shortcut to the BLE mesh TestScreen.
/// TODO: remove after Milestone 3 two-phone peer test is signed off.
class _MeshTestButton extends StatelessWidget {
  const _MeshTestButton();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.push(AppRoutes.test),
      icon: const Icon(Icons.radar_rounded, size: 16),
      label: const Text('Mesh Test Screen'),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.secondaryTextColor,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}

// ── Sign-out button ───────────────────────────────────────────────────────────

class _SignOutButton extends ConsumerStatefulWidget {
  const _SignOutButton();

  @override
  ConsumerState<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<_SignOutButton> {
  bool _signingOut = false;

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign Out',
          style: TextStyle(color: AppTheme.primaryTextColor, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppTheme.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.secondaryTextColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                  color: AppTheme.errorColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _signingOut = true);
    try {
      await ref.read(authServiceProvider).signOut();
      // NO explicit context.go() here.
      //
      // Calling context.go('/login') immediately after signOut() was the cause
      // of the sign-out redirect loop: authStateProvider (backed by Firestore
      // snapshots) hadn't emitted null yet, so the router saw isLoggedIn=true
      // and intercepted the /login navigation, bouncing the user back to
      // /attendance.
      //
      // With the RouterNotifier fix, signOut() fires Firebase Auth's
      // authStateChanges(), which propagates to authStateProvider, which calls
      // _RouterNotifier.notifyListeners(), which triggers GoRouter's redirect.
      // The redirect sees isLoggedIn=false and navigates to /login
      // automatically — no explicit call needed.
      //
      // _signingOut is intentionally left true until the screen is unmounted
      // by the router (keeps the spinner visible during the transition).
    } catch (e) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sign out failed. Please try again.'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _signingOut ? null : _handleSignOut,
        icon: _signingOut
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.errorColor),
              )
            : const Icon(Icons.logout, size: 18),
        label: Text(_signingOut ? 'Signing out…' : 'Sign Out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.errorColor,
          side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.secondaryTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.inputBorderColor),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x18000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.secondaryTextColor),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.secondaryTextColor, fontSize: 13)),
          const Spacer(),
          valueWidget ??
              Text(
                value ?? '—',
                style: const TextStyle(
                    color: AppTheme.primaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.inputBorderColor,
      indent: 46,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  Color get _color {
    switch (role.toLowerCase()) {
      case 'teacher':
        return const Color(0xFF8B5CF6);
      case 'security':
        return const Color(0xFFF59E0B);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        role.isEmpty ? '—' : role[0].toUpperCase() + role.substring(1),
        style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BleStatusChip extends StatelessWidget {
  const _BleStatusChip({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.successColor : AppTheme.secondaryTextColor;
    final label = isActive ? 'Active' : 'Idle';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
