import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';

class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color? valueColor;
  final String? badge;
  final Color? badgeColor;
  final bool gradient;
  final Widget? footer;

  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.valueColor,
    this.badge,
    this.badgeColor,
    this.gradient = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    if (gradient) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppDecorations.surfaceGradient(),
        child: _buildContent(isOnGradient: true),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(radius: AppDecorations.radiusLg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: AppDecorations.iconBadge(accentColor, circle: true),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent({bool isOnGradient = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isOnGradient ? AppColors.textMuted : AppColors.textMuted,
                ),
              ),
            ),
            if (badge != null) const SizedBox(width: 8),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppColors.income).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: badgeColor ?? AppColors.income,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: isOnGradient ? 28 : 24,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 14),
          footer!,
        ],
      ],
    );
  }
}
