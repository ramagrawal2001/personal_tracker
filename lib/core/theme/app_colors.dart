import 'package:flutter/material.dart';

/// App colour palette.
///
/// Every token resolves against [brightness], which [AspyricApp] sets on each
/// build from the active [ThemeMode] (System resolves via the platform
/// brightness). Screens keep referencing `AppColors.<name>` exactly as before
/// — the values now follow the light/dark switch instead of being hard-coded
/// dark. Because the tokens are getters they can no longer sit inside `const`
/// expressions.
class AppColors {
  AppColors._();

  /// Flipped by [AspyricApp] before the widget tree under `MaterialApp`
  /// builds. Defaults to dark so any code path that runs before the first
  /// `AspyricApp.build` still gets sensible values.
  static Brightness brightness = Brightness.dark;
  static bool get _d => brightness == Brightness.dark;

  static Color _p(int dark, int light) => Color(_d ? dark : light);

  // Background & Surfaces
  static Color get background => _p(0xFF0F172A, 0xFFF4F6FB);
  static Color get surface => _p(0xFF1E293B, 0xFFFFFFFF);
  static Color get surfaceLight => _p(0xFF334155, 0xFFEDF0F8);
  static Color get cardBg => _p(0xFF1E293B, 0xFFFFFFFF);
  static Color get cardBgElevated => _p(0xFF26334D, 0xFFF1F4FC);

  // Borders & Dividers
  static Color get border => _p(0xFF334155, 0xFFE2E6F1);
  static Color get borderLight => _p(0xFF475569, 0xFFCED5E6);

  // Typography
  static Color get textPrimary => _p(0xFFF8FAFC, 0xFF0F1324);
  static Color get textSecondary => _p(0xFF94A3B8, 0xFF48507A);
  static Color get textMuted => _p(0xFF64748B, 0xFF5B6480);

  // Brand / Accents (indigo brand keeps its hue in both modes)
  static Color get primary => _p(0xFF6366F1, 0xFF5457E6);
  static Color get primaryLight => _p(0xFF818CF8, 0xFF4F46E5);
  static Color get accent => _p(0xFF0EA5E9, 0xFF0284C7);

  // Financial semantics
  static Color get income => _p(0xFF10B981, 0xFF047E58);
  static Color get incomeBg => _p(0xFF064E3B, 0xFFD1FAE5);

  static Color get expense => _p(0xFFF43F5E, 0xFFE11D48);
  static Color get expenseBg => _p(0xFF4C0519, 0xFFFFE4E6);

  static Color get transfer => _p(0xFF8B5CF6, 0xFF7C3AED);
  static Color get transferBg => _p(0xFF3B0764, 0xFFEDE9FE);

  static Color get creditCard => _p(0xFFF59E0B, 0xFFB45309);
  static Color get loan => _p(0xFFEC4899, 0xFFDB2777);

  static Color get warning => _p(0xFFF59E0B, 0xFFB45309);
  static Color get info => _p(0xFF3B82F6, 0xFF2563EB);
  static Color get success => _p(0xFF10B981, 0xFF047E58);
}
