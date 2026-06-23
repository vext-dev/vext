import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_service_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Auto-focus email field after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Navigation after successful login is typically handled by an auth
      // state listener (e.g. a router redirect). If you need explicit
      // navigation here, add it below:
      // if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(_friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Maps raw exceptions / error messages to user-friendly strings.
  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('user-not-found') ||
        message.contains('wrong-password') ||
        message.contains('invalid-credential')) {
      return 'Incorrect email or password. Please try again.';
    } else if (message.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    } else if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('connection')) {
      return 'Network error. Please check your connection.';
    } else if (message.contains('user-disabled')) {
      return 'This account has been disabled. Contact support.';
    } else if (message.contains('invalid-email') ||
        message.contains('bmsce')) {
      return 'Only @bmsce.ac.in email addresses are allowed.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.errorColor, // use your theme color
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

    return GestureDetector(
      // Dismiss keyboard when tapping outside any input
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Stack(
          children: [
            // ── Mesh background ────────────────────────────────────────────
            Positioned.fill(
              child: CustomPaint(painter: _MeshBackgroundPainter()),
            ),
            // ── Top vignette to help text readability ──────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 280,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.backgroundColor,
                      AppTheme.backgroundColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // ── Form content ───────────────────────────────────────────────
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Logo ──────────────────────────────────────────────
                      const _VextLogo(),
                      const SizedBox(height: 48),

                  // ── Headline ────────────────────────────────────────────
                  Text(
                    'Welcome back',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.primaryTextColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to continue',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── Form ────────────────────────────────────────────────
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Email
                        _InputLabel(label: 'Email'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          onFieldSubmitted: (_) =>
                              _passwordFocusNode.requestFocus(),
                          validator: _validateEmail,
                          style: TextStyle(color: AppTheme.primaryTextColor),
                          decoration: _inputDecoration(
                            hint: 'you@example.com',
                            prefixIcon: Icons.email_outlined,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Password
                        _InputLabel(label: 'Password'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _handleLogin(),
                          validator: _validatePassword,
                          style: TextStyle(color: AppTheme.primaryTextColor),
                          decoration: _inputDecoration(
                            hint: '••••••••',
                            prefixIcon: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppTheme.secondaryTextColor,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Login button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: AppTheme.onPrimaryColor,
                              disabledBackgroundColor:
                                  AppTheme.primaryColor.withValues(alpha: 0.5),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppTheme.onPrimaryColor,
                                    ),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Sign up link ─────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: TextStyle(
                          color: AppTheme.secondaryTextColor,
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.push(AppRoutes.signup),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                    ],                  // Column.children
                  ),                    // Column
                ),                      // SingleChildScrollView
              ),                        // Center
            ),                          // SafeArea
          ],                            // Stack.children
        ),                              // Stack
      ),                                // Scaffold
    );                                  // GestureDetector / return
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.secondaryTextColor.withValues(alpha: 0.6)),
      prefixIcon: Icon(prefixIcon, color: AppTheme.secondaryTextColor, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppTheme.inputFillColor,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.inputBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.inputBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.errorColor, width: 1.5),
      ),
      errorStyle: TextStyle(color: AppTheme.errorColor, fontSize: 12),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// VEXT brand logo — icon + glowing wordmark + tagline.
class _VextLogo extends StatelessWidget {
  const _VextLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Hub icon with glow ring ──────────────────────────────────────
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.cardColor,
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: AppTheme.primaryGlow(intensity: 0.8),
          ),
          child: const Icon(
            Icons.hub_outlined,
            color: AppTheme.accentColor,
            size: 34,
          ),
        ),

        const SizedBox(height: 20),

        // ── VEXT wordmark — glowing signal cyan ──────────────────────────
        const Text(
          'VEXT',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.accentColor, // #22D3EE — lighter signal cyan
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
            shadows: AppTheme.primaryTextGlow, // cyan glow
          ),
        ),

        const SizedBox(height: 10),

        // ── Tagline ──────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 1,
              color: AppTheme.inputBorderColor,
            ),
            const SizedBox(width: 10),
            const Text(
              'CAMPUS MESH INTELLIGENCE',
              style: TextStyle(
                color: AppTheme.hintTextColor,
                fontSize: 9.5,
                letterSpacing: 2.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 24,
              height: 1,
              color: AppTheme.inputBorderColor,
            ),
          ],
        ),
      ],
    );
  }
}

/// Small label above each form field.
class _InputLabel extends StatelessWidget {
  const _InputLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppTheme.primaryTextColor,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
  }
}

// ── Mesh background ────────────────────────────────────────────────────────────

/// Paints a subtle hexagonal-style mesh node grid — evokes BLE mesh topology.
/// All colours are very low opacity so they don't compete with the form UI.
class _MeshBackgroundPainter extends CustomPainter {
  const _MeshBackgroundPainter();

  // Spacing between nodes in logical pixels.
  static const double _hSpacing = 52.0;
  static const double _vSpacing = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.14)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    final diagPaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.07)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;

    final activeDotPaint = Paint()
      ..color = const Color(0xFF22D3EE).withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;

    final cols = (size.width / _hSpacing).ceil() + 2;
    final rows = (size.height / _vSpacing).ceil() + 2;

    // Predefined "active" node positions for visual interest
    const activeSet = {3, 11, 19, 27, 35, 42};

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Stagger odd rows by half a column width (honeycomb feel)
        final xOffset = r.isOdd ? _hSpacing * 0.5 : 0.0;
        final x = c * _hSpacing + xOffset - _hSpacing;
        final y = r * _vSpacing - _vSpacing;

        final nodeIndex = r * cols + c;
        final isActive = activeSet.contains(nodeIndex % 50);

        // Horizontal connection → right neighbour
        if (c < cols - 1) {
          final nx = (c + 1) * _hSpacing + xOffset - _hSpacing;
          canvas.drawLine(Offset(x, y), Offset(nx, y), linePaint);
        }

        // Diagonal connection ↘ (alternating cells to avoid over-crowding)
        if (r < rows - 1 && c < cols - 1 && (r + c).isEven) {
          final nextOffset = r.isOdd ? 0.0 : _hSpacing * 0.5;
          canvas.drawLine(
            Offset(x, y),
            Offset((c + 1) * _hSpacing + nextOffset - _hSpacing,
                (r + 1) * _vSpacing - _vSpacing),
            diagPaint,
          );
        }

        // Node dot
        canvas.drawCircle(
          Offset(x, y),
          isActive ? 3.0 : 1.8,
          isActive ? activeDotPaint : dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MeshBackgroundPainter _) => false;
}
