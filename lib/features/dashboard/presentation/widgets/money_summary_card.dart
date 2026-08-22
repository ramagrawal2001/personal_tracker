import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricCard(
                'Bank Balance',
                CurrencyFormatter.format(bankBalance),
                LucideIcons.landmark,
                AppColors.accent,
              ),
              _buildMetricCard(
                'Credit Card Due',
                CurrencyFormatter.format(creditCardDue),
                LucideIcons.creditCard,
                AppColors.creditCard,
              ),
              _buildMetricCard(
                'Upcoming EMIs',
                CurrencyFormatter.format(upcomingEmis),
                LucideIcons.clock,
                AppColors.loan,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('THIS MONTH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted)),
                    Text(
                      'Savings: ${CurrencyFormatter.format(remainingIncome > 0 ? remainingIncome : 0.0)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.income),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.arrowDownLeft, color: AppColors.income, size: 16),
                        const SizedBox(width: 4),
                        Text('Income: ${CurrencyFormatter.format(monthlyIncome)}', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(LucideIcons.arrowUpRight, color: AppColors.expense, size: 16),
                        const SizedBox(width: 4),
                        Text('Expenses: ${CurrencyFormatter.format(monthlyExpenses)}', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
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
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
