import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/summary_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/empty_state.dart';

/// One of the three stats in the Reports hero-card footer. Wrapped in
/// [Expanded] with a scale-down value so long currency amounts (e.g. lakhs)
/// never overflow the row on narrow screens.
Widget _reportStat(String label, String value, Color color, CrossAxisAlignment align) {
  return Expanded(
    child: Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    ),
  );
}

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final income = financeState.monthlyIncome;
    final expenses = financeState.monthlyExpenses;
    final savings = income - expenses;
    final savingsRate = income > 0 ? (savings / income) * 100 : 0.0;

    final now = DateTime.now();
    final monthTxns = financeState.transactions.where((t) =>
      t.type == TransactionType.expense &&
      t.date.year == now.year &&
      t.date.month == now.month
    ).toList();

    final Map<String, double> catSpend = {};
    for (final t in monthTxns) {
      final catId = t.categoryId ?? 'Other';
      catSpend[catId] = (catSpend[catId] ?? 0) + t.amount;
    }
    final sortedCats = catSpend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    String getCatName(String id) {
      final match = financeState.categories.where((c) => c.id == id);
      if (match.isNotEmpty) return match.first.name;
      if (id.startsWith('cat_')) {
        return id.substring(4).replaceAll('_', ' ').toUpperCase();
      }
      return id;
    }
    final palette = [
      AppColors.primary,
      AppColors.warning,
      AppColors.expense,
      AppColors.accent,
      AppColors.transfer,
      AppColors.income,
      AppColors.loan,
    ];

    return AppScaffold(
      title: 'Financial Reports',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monthly Summary Hero Card
          SummaryCard(
            label: 'Current Month Financial Summary',
            value: CurrencyFormatter.format(savings > 0 ? savings : 0),
            icon: LucideIcons.barChart3,
            accentColor: AppColors.income,
            gradient: true,
            badge: '${savingsRate.toStringAsFixed(1)}% Savings Rate',
            badgeColor: savingsRate >= 20 ? AppColors.income : AppColors.warning,
            footer: Row(
              children: [
                _reportStat('Total Income', CurrencyFormatter.format(income),
                    AppColors.income, CrossAxisAlignment.start),
                Container(height: 30, width: 1, color: AppColors.border),
                _reportStat('Total Expenses', CurrencyFormatter.format(expenses),
                    AppColors.expense, CrossAxisAlignment.center),
                Container(height: 30, width: 1, color: AppColors.border),
                _reportStat(
                    'Net Savings',
                    CurrencyFormatter.format(savings),
                    savings >= 0 ? AppColors.primary : AppColors.expense,
                    CrossAxisAlignment.end),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Expense Distribution'),

          if (sortedCats.isEmpty)
            const EmptyState(
              icon: LucideIcons.pieChart,
              title: 'No expenses recorded',
              description: 'Log your daily expenses to see a categorized breakdown and visual analytics.',
            )
          else ...[
            // FL Chart Pie Chart Card
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 44,
                        sections: sortedCats.asMap().entries.map((entry) {
                          final i = entry.key;
                          final e = entry.value;
                          final color = palette[i % palette.length];
                          final catName = getCatName(e.key);
                          final pct = expenses > 0 ? (e.value / expenses * 100).toStringAsFixed(0) : '0';
                          return PieChartSectionData(
                            value: e.value,
                            title: '$catName\n$pct%',
                            color: color,
                            radius: 44,
                            titleStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const SectionHeader(title: 'Top Expense Categories'),

            ...sortedCats.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final color = palette[i % palette.length];
              final catName = getCatName(e.key);
              final pct = expenses > 0 ? (e.value / expenses * 100).toStringAsFixed(1) : '0.0';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          catName,
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 14),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        CurrencyFormatter.format(e.value),
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
