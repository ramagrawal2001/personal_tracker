import 'package:flutter/material.dart';

/// App colour palette — "Cobalt" theme.
///
/// A cohesive near-black / cool-grey neutral ramp + a single electric-blue
/// accent, tuned for WCAG 2.1 AA in BOTH light and dark. Every token resolves
/// against [brightness].
///
/// [brightness] has exactly ONE authoritative writer at runtime: `PaletteScope`
/// (`lib/core/theme/palette_scope.dart`), mounted from `MaterialApp.builder`,
/// which sets it from the non-animated `themeProvider` value + the platform
/// brightness before any routed screen paints. `main()` seeds it once more from
/// the persisted mode so the very first frame is correct too.
///
/// Screens keep referencing `AppColors.<name>` exactly as before — only the
/// values changed. Because the tokens are getters they can't sit inside
/// `const` expressions.
class AppColors {
  AppColors._();

  /// Set by `PaletteScope` (authoritative) and seeded by `main()`. Defaults to
  /// dark so any code path that runs before the first build still gets sensible
  /// values.
  static Brightness brightness = Brightness.dark;
  static bool get _d => brightness == Brightness.dark;

  static Color _p(int dark, int light) => Color(_d ? dark : light);

  // ── Background & surfaces (cool-grey / near-black ramp) ─────────────────
  static Color get background => _p(0xFF0A0C10, 0xFFF5F7FB);
  static Color get surface => _p(0xFF14171D, 0xFFFFFFFF);
  static Color get surfaceLight => _p(0xFF1C212B, 0xFFEEF2F8);
  static Color get cardBg => _p(0xFF14171D, 0xFFFFFFFF);
  static Color get cardBgElevated => _p(0xFF1F2831, 0xFFF7F9FC);

  /// Middle stop of [AppDecorations.surfaceGradient] — a barely-there shift so
  /// the surface reads as one flat panel, not a gradient.
  static Color get heroGradientMid => _p(0xFF171B22, 0xFFEEF2F8);

  /// Deep, solid blue used for the one branded "hero" card (Net Worth). It is
  /// intentionally mode-independent: white text sits on it at ~5.9:1 in both
  /// themes.
  static const Color heroSurface = Color(0xFF1D4ED8);
  static const Color heroSurfaceAlt = Color(0xFF1E40AF);

  // ── Borders & dividers ─────────────────────────────────────────────────
  static Color get border => _p(0xFF262C37, 0xFFE2E8F0);
  static Color get borderLight => _p(0xFF3A4653, 0xFFCBD5E1);

  // ── Typography ────────────────────────────────────────────────────────
  static Color get textPrimary => _p(0xFFF3F5F8, 0xFF0B1220);
  static Color get textSecondary => _p(0xFFA9B4BF, 0xFF46536A);
  static Color get textMuted => _p(0xFF8B93A1, 0xFF5B6472);

  // ── Brand / accent (electric blue) ────────────────────────────────────
  /// The one confident accent. Bright blue in dark, deeper blue in light.
  static Color get primary => _p(0xFF3B82F6, 0xFF2563EB);
  static Color get primaryLight => _p(0xFF60A5FA, 0xFF3B82F6);

  /// Text/icon colour that sits ON [primary] as a fill (buttons, FAB).
  static Color get onPrimary => _p(0xFFFFFFFF, 0xFFFFFFFF);

  /// Secondary accent — a lighter blue, used where call sites already
  /// reference `AppColors.accent`.
  static Color get accent => _p(0xFF60A5FA, 0xFF2563EB);

  // ── Financial semantics ───────────────────────────────────────────────
  // Light-mode value is green-800, not the brighter green-600: green-600
  // only hits ~2.9:1 against surfaceLight/background as text — below WCAG.
  // Darker green stays a strict contrast win everywhere else it's used too
  // (icons, and as a solid background under white text).
  static Color get income => _p(0xFF22C55E, 0xFF166534);
  static Color get incomeBg => _p(0xFF0C2A18, 0xFFDCF5E3);

  static Color get expense => _p(0xFFF43F5E, 0xFFDC2626);
  static Color get expenseBg => _p(0xFF2E1416, 0xFFFCE4E4);

  static Color get transfer => _p(0xFFA5B4FC, 0xFF4338CA);
  static Color get transferBg => _p(0xFF1E2140, 0xFFE7E9FB);

  static Color get creditCard => _p(0xFFFBBF24, 0xFFB45309);
  static Color get loan => _p(0xFFFB7185, 0xFFBE185D);

  /// [loan], darkened for use as a solid button background under white text
  /// (the un-darkened dark-mode value only hits ~2.7:1 contrast with white —
  /// below WCAG AA). Safe to use in both modes: light mode's [loan] already
  /// passes AA (~6:1) and the extra blend keeps it well clear of the floor.
  static Color get loanButtonBg =>
      Color.alphaBlend(Colors.black.withValues(alpha: 0.30), loan);

  static Color get warning => _p(0xFFFBBF24, 0xFFB45309);
  static Color get info => _p(0xFF60A5FA, 0xFF2563EB);
  static Color get success => _p(0xFF22C55E, 0xFF16A34A);

  // ── Effects ───────────────────────────────────────────────────────────
  /// Soft shadow colour for elevated surfaces — heavier alpha in dark (over
  /// near-black), very light in light mode. No glow.
  static Color get shadow => _d
      ? const Color(0xFF000000).withValues(alpha: 0.45)
      : const Color(0xFF0B1220).withValues(alpha: 0.08);

  /// Modal scrim.
  static Color get scrim => _d
      ? const Color(0xFF000000).withValues(alpha: 0.60)
      : const Color(0xFF0B1220).withValues(alpha: 0.40);
}
