import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_card.dart';

class MoneySummaryCard extends StatelessWidget {
  final double bankBalance;
  final double creditCardDue;
  final double upcomingEmis;
  final double monthlyIncome;
  final double monthlyExpenses;

  const MoneySummaryCard({
    super.key,
    required this.bankBalance,
    required this.creditCardDue,
    required this.upcomingEmis,
    required this.monthlyIncome,
    required this.monthlyExpenses,
  });

  @override
  Widget build(BuildContext context) {
    final double remainingIncome = monthlyIncome - monthlyExpenses;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildMetricCard(
                'Bank Balance',
                CurrencyFormatter.format(bankBalance),
                LucideIcons.landmark,
                AppColors.accent,
              ),
              const SizedBox(width: 8),
              _buildMetricCard(
                'Card Due',
                CurrencyFormatter.format(creditCardDue),
                LucideIcons.creditCard,
                AppColors.creditCard,
              ),
              const SizedBox(width: 8),
              _buildMetricCard(
                'Upcoming EMIs',
                CurrencyFormatter.format(upcomingEmis),
                LucideIcons.clock,
                AppColors.loan,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('MONTHLY FLOW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.textSecondary)),
                    Text(
                      'Savings: ${CurrencyFormatter.format(remainingIncome > 0 ? remainingIncome : 0.0)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.income),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.arrowDownLeft, color: AppColors.income, size: 15),
                        const SizedBox(width: 4),
                        Text('In: ${CurrencyFormatter.format(monthlyIncome)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(LucideIcons.arrowUpRight, color: AppColors.expense, size: 15),
                        const SizedBox(width: 4),
                        Text('Out: ${CurrencyFormatter.format(monthlyExpenses)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String amount, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: AppDecorations.iconBadge(color, circle: true),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
