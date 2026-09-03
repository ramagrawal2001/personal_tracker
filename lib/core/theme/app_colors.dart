import 'package:flutter/material.dart';

/// App colour palette — "Evergreen" premium theme.
///
/// A cohesive neutral slate ramp + a single confident **teal** accent, tuned
/// for WCAG 2.1 AA in BOTH light and dark. Every token resolves against
/// [brightness].
///
/// [brightness] has exactly ONE authoritative writer at runtime:
/// `MaterialApp.builder` in `lib/main.dart`, which sets it from
/// `Theme.of(context).brightness` (the fully-resolved effective brightness,
/// System included) before any routed screen paints. `main()` seeds it once
/// more from the persisted mode so the very first frame is correct too.
///
/// Screens keep referencing `AppColors.<name>` exactly as before — only the
/// values changed. Because the tokens are getters they can't sit inside
/// `const` expressions.
class AppColors {
  AppColors._();

  /// Set by `MaterialApp.builder` (authoritative) and seeded by `main()`.
  /// Defaults to dark so any code path that runs before the first build still
  /// gets sensible values.
  static Brightness brightness = Brightness.dark;
  static bool get _d => brightness == Brightness.dark;

  static Color _p(int dark, int light) => Color(_d ? dark : light);

  // ── Background & surfaces (neutral slate ramp) ──────────────────────────
  static Color get background => _p(0xFF0B0F14, 0xFFF5F7F8);
  static Color get surface => _p(0xFF141A21, 0xFFFFFFFF);
  static Color get surfaceLight => _p(0xFF1C242D, 0xFFEDF1F2);
  static Color get cardBg => _p(0xFF141A21, 0xFFFFFFFF);
  static Color get cardBgElevated => _p(0xFF1F2831, 0xFFF7F9FA);

  /// Middle stop of [AppDecorations.surfaceGradient] — a barely-there shift so
  /// the surface reads as one flat panel, not a gradient.
  static Color get heroGradientMid => _p(0xFF18222B, 0xFFEEF2F3);

  /// Deep, solid teal used for the one branded "hero" card (Net Worth). It is
  /// intentionally mode-independent: white text sits on it at ~7.6:1 in both
  /// themes.
  static const Color heroSurface = Color(0xFF115E59);
  static const Color heroSurfaceAlt = Color(0xFF0F766E);

  // ── Borders & dividers ─────────────────────────────────────────────────
  static Color get border => _p(0xFF2A343F, 0xFFDEE4E7);
  static Color get borderLight => _p(0xFF3A4653, 0xFFC7D0D4);

  // ── Typography ────────────────────────────────────────────────────────
  static Color get textPrimary => _p(0xFFF2F5F7, 0xFF0E1519);
  static Color get textSecondary => _p(0xFFA9B4BF, 0xFF4A575F);
  static Color get textMuted => _p(0xFF7C8894, 0xFF5F6E76);

  // ── Brand / accent (teal) ─────────────────────────────────────────────
  /// The one confident accent. Bright mint in dark, deep teal in light.
  static Color get primary => _p(0xFF2DD4BF, 0xFF0F766E);
  static Color get primaryLight => _p(0xFF5EEAD4, 0xFF0D9488);

  /// Text/icon colour that sits ON [primary] as a fill (buttons, FAB).
  /// Near-black ink in dark (mint button), white in light (deep-teal button).
  static Color get onPrimary => _p(0xFF03211E, 0xFFFFFFFF);

  /// Secondary accent — a refined blue, analogous to the teal. Used only where
  /// call sites already reference `AppColors.accent`.
  static Color get accent => _p(0xFF60A5FA, 0xFF2563EB);

  // ── Financial semantics ───────────────────────────────────────────────
  static Color get income => _p(0xFF34D399, 0xFF047857);
  static Color get incomeBg => _p(0xFF0C2A22, 0xFFD9F2E8);

  static Color get expense => _p(0xFFF87171, 0xFFC81E1E);
  static Color get expenseBg => _p(0xFF2E1416, 0xFFFCE4E4);

  static Color get transfer => _p(0xFFC4B5FD, 0xFF6D28D9);
  static Color get transferBg => _p(0xFF241C3A, 0xFFEDE7FB);

  static Color get creditCard => _p(0xFFFBBF24, 0xFFA64B06);
  static Color get loan => _p(0xFFFB7185, 0xFFBE185D);

  static Color get warning => _p(0xFFFBBF24, 0xFF9A5B00);
  static Color get info => _p(0xFF60A5FA, 0xFF2563EB);
  static Color get success => _p(0xFF34D399, 0xFF047857);

  // ── Effects ───────────────────────────────────────────────────────────
  /// Soft shadow colour for elevated surfaces — heavier alpha in dark (over
  /// near-black), very light in light mode. No glow.
  static Color get shadow => _d
      ? const Color(0xFF000000).withValues(alpha: 0.45)
      : const Color(0xFF0E1519).withValues(alpha: 0.08);

  /// Modal scrim.
  static Color get scrim => _d
      ? const Color(0xFF000000).withValues(alpha: 0.60)
      : const Color(0xFF0E1519).withValues(alpha: 0.40);
}
