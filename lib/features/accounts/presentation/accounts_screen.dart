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
        title: const Text('ACCOUNTS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.plus, color: AppColors.primary), onPressed: () => AddAccountModal.show(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.income.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(LucideIcons.wallet, color: AppColors.income, size: 24)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Total Liquid Balance', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(CurrencyFormatter.format(totalLiquid), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ])),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Your Accounts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            if (accounts.isEmpty)
              _emptyState(context)
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
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Icon(acc.type == AccountType.cash ? LucideIcons.banknote : LucideIcons.landmark, color: AppColors.primary, size: 22)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(acc.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text('${acc.type.displayName}${acc.accountNumberLast4 != null ? " •••• ${acc.accountNumberLast4}" : ""}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(CurrencyFormatter.format(acc.calculatedBalance), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.income, fontSize: 16)),
                        const Text('Balance', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      ]),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
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
                    ]),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
    child: Column(children: [
      const Icon(LucideIcons.wallet, color: AppColors.textMuted, size: 48),
      const SizedBox(height: 16),
      const Text('No accounts yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      const Text('Add your bank account, cash wallet or savings account.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: () => AddAccountModal.show(context),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Add Account'),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ]),
  );

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
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, acc) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete Account?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: Text('Delete "${acc.name}"? Linked transactions remain.', style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteAccount(acc.id); Navigator.pop(ctx); },
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 16, color: AppColors.textMuted),
    filled: true, fillColor: AppColors.surfaceLight,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
    labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
  );
}
