import 'package:flutter/material.dart';

class SnyderColors {
  static const bg = Color(0xFF040913);
  static const bg2 = Color(0xFF07111D);
  static const panel = Color(0xF20A1422);
  static const panel2 = Color(0xFF0E1A2A);
  static const line = Color(0xFF29445E);
  static const cyan = Color(0xFF38E9FF);
  static const blue = Color(0xFF3A8DFF);
  static const violet = Color(0xFFAE7BFF);
  static const lavender = Color(0xFFD9C0FF);
  static const silver = Color(0xFFE2E8F2);
  static const green = Color(0xFF4BE6A4);
  static const warning = Color(0xFFFFCA63);
  static const danger = Color(0xFFFF7182);
  static const muted = Color(0xFF99AEC3);
  static const text = Color(0xFFF7F9FF);
}

ThemeData snyderTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SnyderColors.cyan,
    brightness: Brightness.dark,
    surface: SnyderColors.panel,
  );
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: SnyderColors.bg,
    colorScheme: scheme,
    dividerColor: SnyderColors.line,
    fontFamily: 'sans-serif',
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF06101A),
      indicatorColor: Color(0x3338E9FF),
      height: 72,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SnyderColors.panel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SnyderColors.panel2,
      labelStyle: const TextStyle(color: SnyderColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SnyderColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SnyderColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SnyderColors.cyan, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFF001015),
        backgroundColor: SnyderColors.cyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SnyderColors.silver,
        side: const BorderSide(color: SnyderColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: SnyderColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}