import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final income = financeState.monthlyIncome;
    final expenses = financeState.monthlyExpenses;
    final savings = income - expenses;
    final savingsRate = income > 0 ? (savings / income) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'FINANCIAL REPORTS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Monthly Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AUGUST FINANCIAL SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted)),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStat('Income', CurrencyFormatter.format(income), AppColors.income),
                      _buildStat('Expenses', CurrencyFormatter.format(expenses), AppColors.expense),
                      _buildStat('Savings Rate', '${savingsRate.toStringAsFixed(1)}%', AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Expense Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            // FL Chart Pie Chart
            Container(
              height: 220,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 45,
                  sections: [
                    PieChartSectionData(value: 8500, title: 'Food\n8.5k', color: AppColors.warning, radius: 45, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    PieChartSectionData(value: 7200, title: 'Shop\n7.2k', color: AppColors.expense, radius: 45, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    PieChartSectionData(value: 4800, title: 'Fuel\n4.8k', color: AppColors.accent, radius: 45, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    PieChartSectionData(value: 5200, title: 'Bills\n5.2k', color: AppColors.primary, radius: 45, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    PieChartSectionData(value: 30000, title: 'EMI\n30k', color: AppColors.loan, radius: 45, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Category Breakdown Table
            const Text('Top Categories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            _buildCategoryRow('Home Loan EMI', '₹30,000', AppColors.loan),
            _buildCategoryRow('Food & Dining', '₹8,500', AppColors.warning),
            _buildCategoryRow('Shopping', '₹7,200', AppColors.expense),
            _buildCategoryRow('Bills & Utilities', '₹5,200', AppColors.primary),
            _buildCategoryRow('Transport & Fuel', '₹4,800', AppColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildCategoryRow(String name, String amount, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14))),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14)),
        ],
      ),
    );
  }
}
