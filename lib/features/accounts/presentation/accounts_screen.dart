import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/summary_card.dart';
import 'add_account_modal.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final accounts = financeState.accountsWithCalculatedBalances;
    final totalLiquid = financeState.totalLiquidBalance;

    return AppScaffold(
      title: 'Accounts',
      actions: [
        AppScaffold.addAction(onPressed: () => AddAccountModal.show(context)),
      ],
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummaryCard(
            label: 'Total Liquid Balance',
            value: CurrencyFormatter.format(totalLiquid),
            icon: LucideIcons.wallet,
            accentColor: AppColors.income,
            valueColor: AppColors.textPrimary,
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Your Accounts'),
          if (accounts.isEmpty)
            EmptyState(
              icon: LucideIcons.wallet,
              title: 'No accounts yet',
              description: 'Add your bank account, cash wallet, or savings account to track balances.',
              actionLabel: 'Add Account',
              onAction: () => AddAccountModal.show(context),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final acc = accounts[index];
                return AppListTile(
                  icon: acc.type == AccountType.cash ? LucideIcons.banknote : LucideIcons.landmark,
                  iconColor: AppColors.primary,
                  title: acc.name,
                  subtitle: '${acc.type.displayName}${acc.accountNumberLast4 != null ? " •••• ${acc.accountNumberLast4}" : ""}',
                  trailing: CurrencyFormatter.format(acc.calculatedBalance),
                  trailingColor: AppColors.income,
                  menuButton: PopupMenuButton<String>(
                    icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Edit', style: TextStyle(color: AppColors.textPrimary))])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 14, color: AppColors.expense), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.expense))])),
                    ],
                    onSelected: (v) {
                      if (v == 'edit') _showEditSheet(context, ref, acc);
                      if (v == 'delete') _confirmDelete(context, ref, acc);
                    },
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, acc) {
    final nameCtrl = TextEditingController(text: acc.name);
    final bankCtrl = TextEditingController(text: acc.bank ?? '');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Account Name', LucideIcons.wallet)),
            const SizedBox(height: 12),
            TextField(controller: bankCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Bank (optional)', LucideIcons.building2)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                ref.read(financeNotifierProvider.notifier).updateAccount(acc.id, name: nameCtrl.text.trim(), bank: bankCtrl.text.trim().isEmpty ? null : bankCtrl.text.trim());
                Navigator.pop(context);
              },
              child: const Text('Save Changes'),
            )),
          ]),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, acc) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete Account?'),
      content: Text('Delete "${acc.name}"? Linked transactions remain.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteAccount(acc.id); Navigator.pop(ctx); },
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 16, color: AppColors.textMuted),
  );
}
