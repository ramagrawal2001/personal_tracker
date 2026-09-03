import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_scaffold.dart';
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

    return AppScaffold(
      title: 'Dashboard',
      titleWidget: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/app_logo.jpg',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                DateFormat('MMMM yyyy').format(DateTime.now()),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(LucideIcons.user, color: AppColors.textPrimary, size: 18),
          ),
          onPressed: () => context.push('/profile'),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(financeNotifierProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: context.responsiveHorizontalPadding(),
            vertical: 12,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTwoColumn = constraints.maxWidth >= 600;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Net Worth Card - Full width
                  SizedBox(
                    width: double.infinity,
                    child: NetWorthCard(
                      netWorth: financeState.netWorth,
                      totalAssets: financeState.totalAssets,
                      totalLiabilities: financeState.totalLiabilities,
                      onTap: () => context.push('/net-worth'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Safe to Spend & Money Summary - Side by side on tablet
                  if (isTwoColumn) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SafeToSpendCard(
                            safeToSpend: financeState.safeToSpend,
                            liquidBalance: financeState.totalLiquidBalance,
                            upcomingPayments: financeState.upcomingPaymentsTotal,
                            emergencyBuffer: financeState.emergencyBuffer,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: MoneySummaryCard(
                            bankBalance: financeState.totalLiquidBalance,
                            creditCardDue: financeState.totalCreditCardDebt,
                            upcomingEmis: financeState.totalMonthlyEmi,
                            monthlyIncome: financeState.monthlyIncome,
                            monthlyExpenses: financeState.monthlyExpenses,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    SafeToSpendCard(
                      safeToSpend: financeState.safeToSpend,
                      liquidBalance: financeState.totalLiquidBalance,
                      upcomingPayments: financeState.upcomingPaymentsTotal,
                      emergencyBuffer: financeState.emergencyBuffer,
                    ),
                    const SizedBox(height: 14),
                    MoneySummaryCard(
                      bankBalance: financeState.totalLiquidBalance,
                      creditCardDue: financeState.totalCreditCardDebt,
                      upcomingEmis: financeState.totalMonthlyEmi,
                      monthlyIncome: financeState.monthlyIncome,
                      monthlyExpenses: financeState.monthlyExpenses,
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Upcoming Payments & Recent Transactions - Side by side on tablet
                  if (isTwoColumn) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: UpcomingPaymentsWidget(
                            upcomingPayments: financeState.recurringPayments,
                            onViewAll: () => context.push('/recurring'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: RecentTransactionsWidget(
                            transactions: financeState.transactions,
                            onViewAll: () => context.go('/transactions'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    UpcomingPaymentsWidget(
                      upcomingPayments: financeState.recurringPayments,
                      onViewAll: () => context.push('/recurring'),
                    ),
                    const SizedBox(height: 20),
                    RecentTransactionsWidget(
                      transactions: financeState.transactions,
                      onViewAll: () => context.go('/transactions'),
                    ),
                  ],
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
