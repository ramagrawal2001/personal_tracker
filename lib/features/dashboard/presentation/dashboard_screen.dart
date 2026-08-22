import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import 'widgets/net_worth_card.dart';
import 'widgets/safe_to_spend_card.dart';
import 'widgets/money_summary_card.dart';
import 'widgets/upcoming_payments_widget.dart';
import 'widgets/recent_transactions_widget.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FINANCIAL DASHBOARD',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: AppColors.textMuted),
            ),
            Text(
              'August 2026',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bot, color: AppColors.primary),
            onPressed: () => context.go('/ai-assistant'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.bell, color: AppColors.textPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No new alerts. Your finances are healthy!')),
              );
            },
          ),
          const SizedBox(width: 8),
        ],

      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Trigger state refresh
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Net Worth Header Card
              NetWorthCard(
                netWorth: financeState.netWorth,
                totalAssets: financeState.totalAssets,
                totalLiabilities: financeState.totalLiabilities,
                onTap: () => context.go('/net-worth'),
              ),
              const SizedBox(height: 16),

              // 2. Safe to Spend Cushion Engine
              SafeToSpendCard(
                safeToSpend: financeState.safeToSpend,
                liquidBalance: financeState.totalLiquidBalance,
                upcomingPayments: financeState.upcomingPaymentsTotal,
              ),
              const SizedBox(height: 16),

              // 3. Money Overview & Monthly Cashflow
              MoneySummaryCard(
                bankBalance: financeState.totalLiquidBalance,
                creditCardDue: financeState.totalCreditCardDebt,
                upcomingEmis: financeState.totalLoanDebt > 0 ? 30000.0 : 0.0,
                monthlyIncome: financeState.monthlyIncome,
                monthlyExpenses: financeState.monthlyExpenses,
              ),
              const SizedBox(height: 20),

              // 4. Upcoming Obligations / Future Payments
              UpcomingPaymentsWidget(
                upcomingPayments: financeState.recurringPayments,
                onViewAll: () => context.go('/recurring'),
              ),
              const SizedBox(height: 20),

              // 5. Recent Transaction Ledger
              RecentTransactionsWidget(
                transactions: financeState.transactions,
                onViewAll: () => context.go('/transactions'),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
