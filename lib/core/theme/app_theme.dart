import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material [ThemeData] for both modes.
///
/// This file is intentionally self-contained (no `AppColors` reference): the
/// ambient `AppColors` palette is for screen widgets, whereas `theme` /
/// `darkTheme` are evaluated eagerly by `MaterialApp` and must not depend on
/// mutable global state. The values here mirror the `AppColors` tokens.
class AppTheme {
  // Shared brand hue.
  static const _brandDark = Color(0xFF6366F1);
  static const _brandLight = Color(0xFF5457E6);

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        scaffold: const Color(0xFF0F172A),
        surface: const Color(0xFF1E293B),
        surfaceVar: const Color(0xFF334155),
        border: const Color(0xFF334155),
        textPrimary: const Color(0xFFF8FAFC),
        textSecondary: const Color(0xFF94A3B8),
        textMuted: const Color(0xFF64748B),
        primary: _brandDark,
        accent: const Color(0xFF0EA5E9),
        error: const Color(0xFFF43F5E),
        snackBg: const Color(0xFF26334D),
      );

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        scaffold: const Color(0xFFF4F6FB),
        surface: const Color(0xFFFFFFFF),
        surfaceVar: const Color(0xFFEDF0F8),
        border: const Color(0xFFE2E6F1),
        textPrimary: const Color(0xFF0F1324),
        textSecondary: const Color(0xFF48507A),
        textMuted: const Color(0xFF5B6480),
        primary: _brandLight,
        accent: const Color(0xFF0284C7),
        error: const Color(0xFFE11D48),
        snackBg: const Color(0xFF1F2544),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
    required Color surfaceVar,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color primary,
    required Color accent,
    required Color error,
    required Color snackBg,
  }) {
    final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 32),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 20),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: textMuted, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVar,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primary, width: 2)),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: primary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: 0.2),
        disabledColor: surfaceVar,
        labelStyle: TextStyle(color: textSecondary, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snackBg,
        contentTextStyle: TextStyle(color: brightness == Brightness.dark ? textPrimary : Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceVar,
      ),
      datePickerTheme: DatePickerThemeData(backgroundColor: surface),
      timePickerTheme: TimePickerThemeData(backgroundColor: surface),
      popupMenuTheme: PopupMenuThemeData(color: surface),
    );
  }
}
