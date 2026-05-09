import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_service_provider.dart'; // adjust to your project structure
import '../providers/ble_provider.dart'; // exposes bleActiveProvider, blePeerCountProvider
import '../providers/key_manager_provider.dart'; // exposes keyManagerProvider, hasKeysProvider
import '../providers/user_profile_provider.dart'; // exposes userProfileProvider → UserProfile
import '../theme/app_theme.dart'; // adjust to your project structure

// ── Profile screen ────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: _ProfileColors.background,
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _ProfileColors.accent),
        ),
        error: (err, _) => _ErrorBody(message: err.toString()),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBleScanning = ref.watch(bleActiveProvider);
    final peerCount = ref.watch(blePeerCountProvider);
    final hasKeys = ref.watch(hasKeysProvider);
    final appVersion = ref.watch(appVersionProvider); // e.g. packageInfoProvider

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar + identity ─────────────────────────────────────
            _AvatarHeader(profile: profile),
            const SizedBox(height: 28),

            // ── User details card ─────────────────────────────────────
            _SectionCard(
              title: 'Account',
              children: [
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Name',
                  value: profile.displayName.isNotEmpty
                      ? profile.displayName
                      : '—',
                ),
                _Divider(),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: profile.email,
                ),
                _Divider(),
                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'Role',
                  value: profile.role,
                  valueWidget: _RoleBadge(role: profile.role),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── BLE status card ───────────────────────────────────────
            _SectionCard(
              title: 'Connectivity',
              children: [
                _InfoRow(
                  icon: Icons.bluetooth,
                  label: 'BLE Status',
                  valueWidget: _BleStatusChip(isScanning: isBleScanning),
                ),
                _Divider(),
                _InfoRow(
                  icon: Icons.devices_other_outlined,
                  label: 'Peers Discovered',
                  value: peerCount.toString(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Device / keys card ────────────────────────────────────
            _DeviceCard(profile: profile, hasKeys: hasKeys),
            const SizedBox(height: 24),

            // ── Sign out button ───────────────────────────────────────
            _SignOutButton(),
            const SizedBox(height: 28),

            // ── App version ───────────────────────────────────────────
            Center(
              child: Text(
                appVersion ?? 'v—',
                style: const TextStyle(
                  color: _ProfileColors.muted,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Avatar header ─────────────────────────────────────────────────────────────

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({required this.profile});

  final UserProfile profile;

  String get _initials {
    final parts = profile.displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return profile.displayName.isNotEmpty
        ? profile.displayName[0].toUpperCase()
        : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar circle
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
                color: const Color(0xFF3B82F6).withOpacity(0.35),
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
          profile.displayName.isNotEmpty ? profile.displayName : 'User',
          style: const TextStyle(
            color: _ProfileColors.title,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile.email,
          style: const TextStyle(
            color: _ProfileColors.subtitle,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ── Device / key card ─────────────────────────────────────────────────────────

class _DeviceCard extends ConsumerStatefulWidget {
  const _DeviceCard({required this.profile, required this.hasKeys});

  final UserProfile profile;
  final bool hasKeys;

  @override
  ConsumerState<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends ConsumerState<_DeviceCard> {
  bool _generatingKeys = false;

  Future<void> _handleGenerateKeys() async {
    setState(() => _generatingKeys = true);
    try {
      final keyManager = ref.read(keyManagerProvider);

      // Generate keys locally
      await keyManager.generateIdentityKeys();

      // Upload public key to Firestore
      final pubKeyHash = await keyManager.getPublicKeyHash();
      final uid = widget.profile.uid;
      await ref
          .read(firestoreProvider) // your Firestore provider
          .collection('public_keys')
          .doc(uid)
          .set({'publicKeyHash': pubKeyHash, 'updatedAt': DateTime.now()});

      if (mounted) {
        _showSnackBar('Identity keys generated successfully.', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to generate keys. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _generatingKeys = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? AppTheme.errorColor : _ProfileColors.success,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final fingerprint = ref.watch(deviceFingerprintProvider);

    return _SectionCard(
      title: 'Device Identity',
      children: [
        // Fingerprint row
        _InfoRow(
          icon: Icons.fingerprint,
          label: 'Fingerprint',
          valueWidget: fingerprint != null
              ? _FingerprintChip(fingerprint: fingerprint)
              : const Text(
                  'Not generated',
                  style: TextStyle(
                    color: _ProfileColors.muted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
        ),

        // "Generate Keys" button — shown only when keys are absent
        if (!widget.hasKeys) ...[
          _Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _generatingKeys ? null : _handleGenerateKeys,
                icon: _generatingKeys
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.vpn_key_outlined, size: 18),
                label: Text(
                  _generatingKeys ? 'Generating…' : 'Generate Keys',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ProfileColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      _ProfileColors.accent.withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Sign out button ───────────────────────────────────────────────────────────

class _SignOutButton extends ConsumerStatefulWidget {
  const _SignOutButton();

  @override
  ConsumerState<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<_SignOutButton> {
  bool _signingOut = false;

  Future<void> _handleSignOut() async {
    final confirmed = await _confirmSignOut(context);
    if (!confirmed) return;

    setState(() => _signingOut = true);
    try {
      await ref.read(authServiceProvider).signOut();
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sign out failed. Please try again.'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<bool> _confirmSignOut(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _ProfileColors.cardBackground,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign Out',
          style: TextStyle(
            color: _ProfileColors.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: _ProfileColors.subtitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _ProfileColors.subtitle),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: _ProfileColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
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
                  strokeWidth: 2,
                  color: _ProfileColors.danger,
                ),
              )
            : const Icon(Icons.logout, size: 18),
        label: Text(_signingOut ? 'Signing out…' : 'Sign Out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ProfileColors.danger,
          side: const BorderSide(color: _ProfileColors.dangerBorder),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Reusable section card ─────────────────────────────────────────────────────

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
              color: _ProfileColors.sectionLabel,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _ProfileColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ProfileColors.cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

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
          Icon(icon, size: 18, color: _ProfileColors.iconColor),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: _ProfileColors.subtitle,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          valueWidget ??
              Text(
                value ?? '—',
                style: const TextStyle(
                  color: _ProfileColors.title,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
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
      color: _ProfileColors.divider,
      indent: 46,
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

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
        return _ProfileColors.accent; // student
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        role.isEmpty ? '—' : role[0].toUpperCase() + role.substring(1),
        style: TextStyle(
          color: _color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BleStatusChip extends StatelessWidget {
  const _BleStatusChip({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final color = isScanning ? _ProfileColors.success : _ProfileColors.muted;
    final label = isScanning ? 'Scanning' : 'Not Scanning';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Shows first 8 chars of the public key hash with a copy-to-clipboard action.
class _FingerprintChip extends StatelessWidget {
  const _FingerprintChip({required this.fingerprint});

  final String fingerprint;

  String get _short =>
      fingerprint.length >= 8 ? fingerprint.substring(0, 8) : fingerprint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: fingerprint));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fingerprint copied'),
            backgroundColor: _ProfileColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _ProfileColors.chipBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _ProfileColors.chipBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _short.toUpperCase(),
              style: const TextStyle(
                color: _ProfileColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.copy_outlined,
              size: 12,
              color: _ProfileColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: _ProfileColors.danger, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Failed to load profile',
              style: TextStyle(
                color: _ProfileColors.title,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ProfileColors.subtitle,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Color tokens ──────────────────────────────────────────────────────────────

abstract class _ProfileColors {
  static const Color background = Color(0xFF0D1B2A);
  static const Color cardBackground = Color(0xFF132338);
  static const Color cardBorder = Color(0xFF1E3A56);
  static const Color divider = Color(0xFF1A3352);
  static const Color chipBackground = Color(0xFF0F2035);
  static const Color chipBorder = Color(0xFF1E3A56);

  static const Color accent = Color(0xFF3B82F6);
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerBorder = Color(0xFF7F1D1D);

  static const Color title = Color(0xFFE8EEF6);
  static const Color subtitle = Color(0xFF7A94B0);
  static const Color sectionLabel = Color(0xFF4D7096);
  static const Color muted = Color(0xFF4D7096);
  static const Color iconColor = Color(0xFF4D7096);
}
