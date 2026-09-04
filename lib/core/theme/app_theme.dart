import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Material [ThemeData] for both modes — "Cobalt" theme.
///
/// Self-contained (no `AppColors` reference): `theme` / `darkTheme` are
/// evaluated eagerly by `MaterialApp` and must not depend on mutable global
/// state. The values here mirror the `AppColors` tokens 1:1.
class AppTheme {
  // ── Palette (mirrors AppColors) ────────────────────────────────────────
  static const _brandDark = Color(0xFF3B82F6); // electric blue (dark mode)
  static const _brandLight = Color(0xFF2563EB); // deeper blue   (light mode)
  static const _accentDark = Color(0xFF60A5FA);
  static const _accentLight = Color(0xFF2563EB);

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        scaffold: const Color(0xFF0A0C10),
        surface: const Color(0xFF14171D),
        surfaceVar: const Color(0xFF1C212B),
        elevated: const Color(0xFF1F2831),
        border: const Color(0xFF262C37),
        textPrimary: const Color(0xFFF3F5F8),
        textSecondary: const Color(0xFFA9B4BF),
        textMuted: const Color(0xFF8B93A1),
        primary: _brandDark,
        onPrimary: Colors.white,
        accent: _accentDark,
        error: const Color(0xFFF43F5E),
        snackBg: const Color(0xFF1F2831),
      );

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        scaffold: const Color(0xFFF5F7FB),
        surface: const Color(0xFFFFFFFF),
        surfaceVar: const Color(0xFFEEF2F8),
        elevated: const Color(0xFFF7F9FC),
        border: const Color(0xFFE2E8F0),
        textPrimary: const Color(0xFF0B1220),
        textSecondary: const Color(0xFF46536A),
        textMuted: const Color(0xFF5B6472),
        primary: _brandLight,
        onPrimary: Colors.white,
        accent: _accentLight,
        error: const Color(0xFFDC2626),
        snackBg: const Color(0xFF14171D),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
    required Color surfaceVar,
    required Color elevated,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color primary,
    required Color onPrimary,
    required Color accent,
    required Color error,
    required Color snackBg,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark() : ThemeData.light();

    // Status-bar / nav-bar icons must contrast the scaffold: dark icons in
    // light mode, light icons in dark mode.
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: surface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primary.withValues(alpha: isDark ? 0.20 : 0.12),
        onPrimaryContainer: primary,
        secondary: accent,
        onSecondary: isDark ? const Color(0xFF06214A) : Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceVar,
        onSurfaceVariant: textSecondary,
        outline: border,
        outlineVariant: border,
        error: error,
        onError: Colors.white,
      ),
      // 'Inter' is bundled locally (assets/fonts/Inter-Variable.ttf) — no
      // network fetch, so theme resolution never depends on connectivity.
      // NB: every style below must repeat `fontFamily: 'Inter'` explicitly —
      // .copyWith() replaces each named TextStyle wholesale, so it would
      // otherwise silently drop the family applied above and fall back to
      // the platform default font for exactly the roles most text uses.
      textTheme: base.textTheme.apply(fontFamily: 'Inter').copyWith(
        displayLarge: TextStyle(fontFamily: 'Inter', color: textPrimary, fontWeight: FontWeight.w700, fontSize: 30, letterSpacing: -0.5),
        displayMedium: TextStyle(fontFamily: 'Inter', color: textPrimary, fontWeight: FontWeight.w700, fontSize: 26, letterSpacing: -0.4),
        headlineSmall: TextStyle(fontFamily: 'Inter', color: textPrimary, fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: -0.3),
        titleLarge: TextStyle(fontFamily: 'Inter', color: textPrimary, fontWeight: FontWeight.w700, fontSize: 19, letterSpacing: -0.2),
        titleMedium: TextStyle(fontFamily: 'Inter', color: textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
        titleSmall: TextStyle(fontFamily: 'Inter', color: textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
        bodyLarge: TextStyle(fontFamily: 'Inter', color: textPrimary, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(fontFamily: 'Inter', color: textSecondary, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(fontFamily: 'Inter', color: textMuted, fontSize: 12, height: 1.4),
        labelLarge: TextStyle(fontFamily: 'Inter', color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        titleTextStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        contentTextStyle: TextStyle(color: textSecondary, fontSize: 14, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: (isDark ? Colors.black : const Color(0xFF0E1519))
            .withValues(alpha: isDark ? 0.60 : 0.40),
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
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error, width: 2)),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textSecondary),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: surfaceVar,
          disabledForegroundColor: textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
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
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: isDark ? 0.20 : 0.12),
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: textMuted),
        selectedLabelTextStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: textMuted),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVar,
        selectedColor: primary.withValues(alpha: isDark ? 0.22 : 0.14),
        disabledColor: surfaceVar,
        labelStyle: TextStyle(color: textSecondary, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? onPrimary : textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? primary
            : surfaceVar),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.transparent : border),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snackBg,
        contentTextStyle: TextStyle(
            color: isDark ? textPrimary : Colors.white, fontSize: 14),
        actionTextColor: isDark ? _brandDark : _brandLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceVar,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: snackBg,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: isDark ? textPrimary : Colors.white, fontSize: 12),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: surface,
        hourMinuteColor: surfaceVar,
        dialBackgroundColor: surfaceVar,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        textColor: textPrimary,
      ),
      splashColor: primary.withValues(alpha: 0.10),
      highlightColor: primary.withValues(alpha: 0.06),
    );
  }
}
