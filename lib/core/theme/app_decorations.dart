import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDecorations {
  AppDecorations._();

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;

  /// Flat surface panel: subtle 1px border, no shadow.
  static BoxDecoration card({Color? color, double radius = radiusMd}) =>
      BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      );

  /// Raised panel: still flat-toned, lifted by ONE very soft shadow (no glow).
  static BoxDecoration cardElevated({Color? color, double radius = radiusMd}) =>
      BoxDecoration(
        color: color ?? AppColors.cardBgElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  /// Branded "hero" card — a solid deep teal (mode-independent) with an
  /// almost-imperceptible vertical sheen. White text sits on it at ~7.6:1.
  static BoxDecoration heroGradient({
    List<Color>? colors,
    double radius = radiusLg,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: colors ??
              const [AppColors.heroSurfaceAlt, AppColors.heroSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  /// A plain surface with the faintest tonal shift — reads as one flat panel.
  static BoxDecoration surfaceGradient({
    List<Color>? colors,
    double radius = radiusLg,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: colors ??
              [AppColors.surface, AppColors.heroGradientMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      );

  static BoxDecoration iconBadge(Color color, {bool circle = false}) =>
      BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radiusSm),
      );

  static BoxDecoration alertBanner(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      );
}
