import 'package:flutter/material.dart';

/// Central design token class for VEXT VigilantMesh.
/// All screens import this — never hard-code colours in widgets.
abstract class AppTheme {
  // ── Brand colours ─────────────────────────────────────────────────────────
  /// Cyan — the colour of BLE/radio frequency spectrum visualisation tools.
  static const Color primaryColor = Color(0xFF06B6D4); // signal cyan
  static const Color onPrimaryColor = Color(0xFF000D14); // dark on cyan
  static const Color accentColor = Color(0xFF22D3EE); // lighter signal cyan
  /// Apple emergency red — universally recognised as "urgent".
  static const Color sosColor = Color(0xFFFF3B30);
  /// Electric mesh-green for confirmed/active BLE states.
  static const Color successColor = Color(0xFF10D979);

  // ── Background shades ─────────────────────────────────────────────────────
  /// Near-black with the faintest blue tint — makes cyan elements "glow".
  static const Color backgroundColor = Color(0xFF060E1A);
  static const Color surfaceColor = Color(0xFF0A1520); // elevated surface
  static const Color cardColor = Color(0xFF0F1D30); // card background
  static const Color navBackgroundColor = Color(0xFF0C1828);

  // ── Text colours ──────────────────────────────────────────────────────────
  static const Color primaryTextColor = Color(0xFFEDF4FF); // cool white
  static const Color secondaryTextColor = Color(0xFF7EA8C8);
  static const Color hintTextColor = Color(0xFF3C6080);

  // ── Input field colours ───────────────────────────────────────────────────
  static const Color inputFillColor = Color(0xFF0F1D30);
  static const Color inputBorderColor = Color(0xFF0D2646);
  static const Color errorColor = Color(0xFFFF3B30); // matches sosColor

  // ── Navigation ────────────────────────────────────────────────────────────
  static const Color navBorderColor = Color(0xFF0D2646);
  static const Color selectedNavItem = Color(0xFF22D3EE); // accent cyan
  static const Color unselectedNavItem = Color(0xFF3C5870);

  // ── BLE indicator ─────────────────────────────────────────────────────────
  static const Color bleActiveColor = Color(0xFF10D979); // electric mesh-green
  static const Color bleInactiveColor = Color(0xFF374060);

  // ── Gradients ─────────────────────────────────────────────────────────────

  /// Signal cyan gradient — primary → accent, top-left → bottom-right.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF22D3EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Emergency gradient — emergency red, top → bottom.
  static const LinearGradient sosGradient = LinearGradient(
    colors: [Color(0xFFFF3B30), Color(0xFFCC1500)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Subtle depth gradient for AppBar / nav backgrounds.
  static const LinearGradient navyDepthGradient = LinearGradient(
    colors: [Color(0xFF0A1C2E), Color(0xFF060E1A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Glow shadows ──────────────────────────────────────────────────────────

  /// Cyan glow — use on primary action buttons, active BLE / signal elements.
  static List<BoxShadow> primaryGlow({double intensity = 1.0}) => [
        BoxShadow(
          color: Color(0xFF06B6D4).withValues(alpha: 0.30 * intensity),
          blurRadius: 20,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: Color(0xFF06B6D4).withValues(alpha: 0.12 * intensity),
          blurRadius: 40,
          spreadRadius: 4,
        ),
      ];

  /// Red glow — use on SOS button, emergency states.
  static List<BoxShadow> sosGlow({double intensity = 1.0}) => [
        BoxShadow(
          color: Color(0xFFFF3B30).withValues(alpha: 0.45 * intensity),
          blurRadius: 24,
          spreadRadius: 4,
        ),
        BoxShadow(
          color: Color(0xFFFF3B30).withValues(alpha: 0.18 * intensity),
          blurRadius: 48,
          spreadRadius: 8,
        ),
      ];

  // ── Text glow (via Shadow) ────────────────────────────────────────────────

  /// Cyan text glow — use on VEXT wordmark, active section titles.
  static const List<Shadow> primaryTextGlow = [
    Shadow(color: Color(0x5506B6D4), blurRadius: 16),
    Shadow(color: Color(0x2822D3EE), blurRadius: 32),
  ];

  // ── Decorated containers ──────────────────────────────────────────────────

  /// Card with a subtle glowing border. [borderColor] defaults to primaryColor.
  static BoxDecoration glowCardDecoration({Color? borderColor}) => BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (borderColor ?? primaryColor).withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (borderColor ?? primaryColor).withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      );

  // ── ThemeData ─────────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: primaryTextColor,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: primaryTextColor,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          color: primaryTextColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        titleMedium: TextStyle(
          color: primaryTextColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: primaryTextColor,
          fontSize: 16,
          height: 1.55,
        ),
        bodyMedium: TextStyle(
          color: secondaryTextColor,
          fontSize: 14,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          color: secondaryTextColor,
          fontSize: 12,
        ),
        labelSmall: TextStyle(
          color: hintTextColor,
          fontSize: 10,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        onPrimary: onPrimaryColor, // dark text on bright cyan
        secondary: accentColor,
        onSecondary: onPrimaryColor,
        error: errorColor,
        surface: surfaceColor,
        onSurface: primaryTextColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: primaryTextColor,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Color(0xFF000000),
        titleTextStyle: TextStyle(
          color: accentColor, // bright cyan wordmark
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimaryColor, // dark text on cyan
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        hintStyle: TextStyle(color: hintTextColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        errorStyle: const TextStyle(color: errorColor, fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: inputBorderColor),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: const TextStyle(color: primaryTextColor),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: const DividerThemeData(
        color: inputBorderColor,
        thickness: 1,
      ),
    );
  }
}
