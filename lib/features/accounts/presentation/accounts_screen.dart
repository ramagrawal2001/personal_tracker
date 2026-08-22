import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import 'add_account_modal.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final accounts = financeState.accountsWithCalculatedBalances;
    final totalLiquid = financeState.totalLiquidBalance;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'ACCOUNTS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, color: AppColors.primary),
            onPressed: () => AddAccountModal.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Liquid Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.income.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.wallet, color: AppColors.income, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Liquid Balance', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        const SizedBox(height: 2),
                        Text(
                          CurrencyFormatter.format(totalLiquid),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Your Accounts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            if (accounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Icon(LucideIcons.wallet, color: AppColors.textMuted, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'No accounts yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your bank account, cash wallet or savings account to track your finances.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => AddAccountModal.show(context),
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: const Text('Add Account'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final acc = accounts[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            acc.type == AccountType.cash ? LucideIcons.banknote : LucideIcons.landmark,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                acc.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${acc.type.displayName}${acc.accountNumberLast4 != null ? " •••• ${acc.accountNumberLast4}" : ""}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.format(acc.calculatedBalance),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.income, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Calculated Balance',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
