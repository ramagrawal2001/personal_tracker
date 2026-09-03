import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/summary_card.dart';
import '../../../core/widgets/section_header.dart';

class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);

    return AppScaffold(
      title: 'Net Worth & Growth',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Net Worth Primary Display
          SummaryCard(
            label: 'Current Net Worth',
            value: CurrencyFormatter.format(financeState.netWorth),
            icon: LucideIcons.wallet,
            accentColor: AppColors.income,
            valueColor: AppColors.income,
            gradient: true,
            footer: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Assets', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(financeState.totalAssets),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                Container(height: 30, width: 1, color: AppColors.border),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Total Liabilities', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(financeState.totalLiabilities),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.expense),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Historical Growth'),

          // Growth Line Chart Card
          AppCard(
            padding: const EdgeInsets.only(right: 16, left: 8, top: 16, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: AppDecorations.iconBadge(AppColors.income, circle: true),
                        child: Icon(LucideIcons.trendingUp, color: AppColors.income, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Liquid Balance Trend — Last 6 Months (Lakhs ₹)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (financeState.transactions.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Add transactions to see your balance trend over time.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: financeState.liquidBalanceTrend().asMap().entries.map((e) {
                              return FlSpot(e.key.toDouble(), e.value / 100000);
                            }).toList(),
                            isCurved: true,
                            color: AppColors.income,
                            barWidth: 3.5,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.income.withValues(alpha: 0.12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Assets Breakdown'),
          AppListTile(
            icon: LucideIcons.banknote,
            iconColor: AppColors.income,
            title: 'Liquid Bank Balances',
            subtitle: 'Savings, current & cash accounts',
            trailing: CurrencyFormatter.format(financeState.totalLiquidBalance),
            trailingColor: AppColors.income,
          ),
          const SizedBox(height: 8),
          AppListTile(
            icon: LucideIcons.trendingUp,
            iconColor: AppColors.primary,
            title: 'Investments & Mutual Funds',
            subtitle: 'Portfolio current valuation',
            trailing: CurrencyFormatter.format(financeState.totalInvestmentCurrentValue),
            trailingColor: AppColors.primary,
          ),

          const SizedBox(height: 24),
          const SectionHeader(title: 'Liabilities Breakdown'),
          AppListTile(
            icon: LucideIcons.creditCard,
            iconColor: AppColors.creditCard,
            title: 'Credit Cards Outstanding',
            subtitle: 'Active statements due',
            trailing: CurrencyFormatter.format(financeState.totalCreditCardDebt),
            trailingColor: AppColors.expense,
          ),
          const SizedBox(height: 8),
          AppListTile(
            icon: LucideIcons.landmark,
            iconColor: AppColors.loan,
            title: 'Active Loans & EMIs',
            subtitle: 'Principal outstanding amount',
            trailing: CurrencyFormatter.format(financeState.totalLoanDebt),
            trailingColor: AppColors.loan,
          ),
        ],
      ),
    );
  }
}
