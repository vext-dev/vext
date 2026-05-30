import 'package:flutter/material.dart';

/// Central design token class for VEXT VigilantMesh.
/// All screens import this — never hard-code colours in widgets.
abstract class AppTheme {
  // ── Brand colours ─────────────────────────────────────────────────────────
  static const Color primaryColor = Color(0xFF3B82F6); // sky blue
  static const Color onPrimaryColor = Color(0xFFFFFFFF);
  static const Color accentColor = Color(0xFF38BDF8); // lighter sky blue
  static const Color sosColor = Color(0xFFEF4444); // emergency red
  static const Color successColor = Color(0xFF22C55E); // BLE active green

  // ── Background shades ─────────────────────────────────────────────────────
  static const Color backgroundColor = Color(0xFF0A1628); // deep navy
  static const Color surfaceColor = Color(0xFF0D1B2A); // slightly lighter navy
  static const Color cardColor = Color(0xFF112240); // card background
  static const Color navBackgroundColor = Color(0xFF0F2035);

  // ── Text colours ──────────────────────────────────────────────────────────
  static const Color primaryTextColor = Color(0xFFE8EDF5);
  static const Color secondaryTextColor = Color(0xFF8BA3C0);
  static const Color hintTextColor = Color(0xFF4D7096);

  // ── Input field colours ───────────────────────────────────────────────────
  static const Color inputFillColor = Color(0xFF112240);
  static const Color inputBorderColor = Color(0xFF1A3352);
  static const Color errorColor = Color(0xFFEF4444);

  // ── Navigation ────────────────────────────────────────────────────────────
  static const Color navBorderColor = Color(0xFF1A3352);
  static const Color selectedNavItem = Color(0xFF38BDF8);
  static const Color unselectedNavItem = Color(0xFF4D7096);

  // ── BLE indicator ─────────────────────────────────────────────────────────
  static const Color bleActiveColor = Color(0xFF22C55E);
  static const Color bleInactiveColor = Color(0xFF4B5563);

  // ── ThemeData ─────────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        onPrimary: onPrimaryColor,
        secondary: accentColor,
        onSecondary: Colors.white,
        error: errorColor,
        surface: surfaceColor,
        onSurface: primaryTextColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: primaryTextColor,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black26,
        titleTextStyle: TextStyle(
          color: primaryColor,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimaryColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
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
