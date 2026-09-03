import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

class SafeToSpendCard extends StatelessWidget {
  final double safeToSpend;
  final double liquidBalance;
  final double upcomingPayments;
  final double emergencyBuffer;

  const SafeToSpendCard({
    super.key,
    required this.safeToSpend,
    required this.liquidBalance,
    required this.upcomingPayments,
    this.emergencyBuffer = 20000.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.shieldCheck, color: AppColors.income, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safe to Spend',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Text(
                      'After upcoming bills & buffer',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                CurrencyFormatter.format(safeToSpend),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.income),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetric('Bank Liquid', CurrencyFormatter.format(liquidBalance)),
              _buildMetric('Upcoming Bills', '- ${CurrencyFormatter.format(upcomingPayments)}', isNegative: true),
              _buildMetric('Emergency Buffer', '- ${CurrencyFormatter.format(emergencyBuffer)}', isMuted: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, {bool isNegative = false, bool isMuted = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isNegative
                ? AppColors.expense
                : isMuted
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
