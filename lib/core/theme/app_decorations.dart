import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDecorations {
  AppDecorations._();

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;

  static BoxDecoration card({Color? color, double radius = radiusMd}) =>
      BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      );

  static BoxDecoration cardElevated({Color? color, double radius = radiusMd}) =>
      BoxDecoration(
        color: color ?? AppColors.cardBgElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration heroGradient({
    List<Color>? colors,
    double radius = radiusLg,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: colors ??
              [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.85),
                const Color(0xFF4F46E5),
              ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration surfaceGradient({
    List<Color>? colors,
    double radius = radiusLg,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: colors ??
              [
                AppColors.surface,
                const Color(0xFF1E1B4B),
                AppColors.background,
              ],
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
