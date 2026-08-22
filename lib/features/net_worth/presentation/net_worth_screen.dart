import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';

class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'NET WORTH',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Net Worth Primary Display
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
                  const Text('CURRENT NET WORTH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Text(
                    CurrencyFormatter.format(financeState.netWorth),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.income),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Assets', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(financeState.totalAssets), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Total Liabilities', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(financeState.totalLiabilities), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.expense)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Historical Growth', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            // Growth Line Chart
            Container(
              height: 200,
              padding: const EdgeInsets.only(right: 16, left: 8, top: 16, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: const [
                        FlSpot(1, 6.2),
                        FlSpot(2, 6.5),
                        FlSpot(3, 6.8),
                        FlSpot(4, 7.1),
                        FlSpot(5, 7.5),
                        FlSpot(6, 7.8),
                        FlSpot(7, 8.1),
                        FlSpot(8, 8.42),
                      ],
                      isCurved: true,
                      color: AppColors.income,
                      barWidth: 4,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.income.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text('Assets Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            _buildRow('Liquid Bank Balance', CurrencyFormatter.format(financeState.totalLiquidBalance), AppColors.income),
            _buildRow('Investments & Mutual Funds', '₹7,50,000', AppColors.primary),
            _buildRow('Fixed Deposits & RDs', '₹3,63,050', AppColors.accent),

            const SizedBox(height: 20),
            const Text('Liabilities Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            _buildRow('Credit Cards Outstanding', CurrencyFormatter.format(financeState.totalCreditCardDebt), AppColors.creditCard),
            _buildRow('Home Loan Balance', CurrencyFormatter.format(financeState.totalLoanDebt), AppColors.loan),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String title, String amount, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 14)),
          Text(amount, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        ],
      ),
    );
  }
}
