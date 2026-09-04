import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/secret_cipher_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/secret_reveal_sheet.dart';
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
                    icon: Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      if (acc.encAccountNumber != null || acc.encIfsc != null)
                        PopupMenuItem(value: 'secrets', child: Row(children: [Icon(LucideIcons.lock, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Bank details', style: TextStyle(color: AppColors.textPrimary))])),
                      PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Edit', style: TextStyle(color: AppColors.textPrimary))])),
                      PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 14, color: AppColors.expense), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.expense))])),
                    ],
                    onSelected: (v) {
                      if (v == 'secrets') _showAccountSecrets(context, acc);
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

  void _showAccountSecrets(BuildContext context, acc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SecretRevealSheet(
        title: '${acc.name} details',
        fields: [
          SecretField('Account number', acc.encAccountNumber,
              maskedFallback: acc.accountNumberLast4 != null ? '•••• ${acc.accountNumberLast4}' : '••••', groupDigits: true),
          SecretField('IFSC / routing', acc.encIfsc, maskedFallback: '••••••'),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, acc) {
    final nameCtrl = TextEditingController(text: acc.name);
    final bankCtrl = TextEditingController(text: acc.bank ?? '');
    final last4Ctrl = TextEditingController(text: acc.accountNumberLast4 ?? '');
    final openingCtrl = TextEditingController(text: acc.openingBalance.toStringAsFixed(0));
    final acctNumCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    AccountType selectedType = acc.type;
    String? error;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Edit Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, style: TextStyle(color: AppColors.textPrimary), decoration: _dec('Account Name', LucideIcons.wallet)),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountType>(
                  isExpanded: true,
                  value: selectedType,
                  decoration: _dec('Account Type', LucideIcons.layers),
                  dropdownColor: AppColors.surface,
                  items: AccountType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName))).toList(),
                  onChanged: (v) => setSheetState(() => selectedType = v ?? selectedType),
                ),
                const SizedBox(height: 12),
                TextField(controller: bankCtrl, style: TextStyle(color: AppColors.textPrimary), decoration: _dec('Bank (optional)', LucideIcons.building2)),
                const SizedBox(height: 12),
                TextField(controller: last4Ctrl, maxLength: 4, keyboardType: TextInputType.number, style: TextStyle(color: AppColors.textPrimary), decoration: _dec('Last 4 digits (optional)', LucideIcons.hash)),
                const SizedBox(height: 12),
                TextField(
                  controller: openingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: _dec('Opening Balance (${CurrencyFormatter.symbol})', LucideIcons.indianRupee).copyWith(errorText: error),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Icon(LucideIcons.lock, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(acc.encAccountNumber != null ? 'Replace sensitive details' : 'Add sensitive details',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: acctNumCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: TextStyle(color: AppColors.textPrimary), decoration: _dec('Full account number (leave blank to keep)', LucideIcons.hash)),
                const SizedBox(height: 12),
                TextField(controller: ifscCtrl, textCapitalization: TextCapitalization.characters, style: TextStyle(color: AppColors.textPrimary), decoration: _dec('IFSC / routing (leave blank to keep)', LucideIcons.landmark)),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final opening = double.tryParse(openingCtrl.text);
                    if (opening == null) {
                      setSheetState(() => error = 'Enter a valid opening balance');
                      return;
                    }
                    if (nameCtrl.text.trim().isEmpty) {
                      setSheetState(() => error = 'Enter an account name');
                      return;
                    }
                    final rawNum = acctNumCtrl.text.replaceAll(RegExp(r'\D'), '');
                    final ifsc = ifscCtrl.text.trim().toUpperCase();
                    String? encNum, encIfsc, newLast4;
                    if (rawNum.isNotEmpty || ifsc.isNotEmpty) {
                      final cipher = ref.read(secretCipherServiceProvider);
                      if (!cipher.isReady) await cipher.restoreFromCache();
                      if (cipher.isReady) {
                        if (rawNum.isNotEmpty) {
                          encNum = cipher.encryptField(rawNum);
                          if (rawNum.length >= 4) newLast4 = rawNum.substring(rawNum.length - 4);
                        }
                        if (ifsc.isNotEmpty) encIfsc = cipher.encryptField(ifsc);
                      } else {
                        setSheetState(() => error = 'Secure storage is locked — sign in again to edit encrypted details');
                        return;
                      }
                    }
                    ref.read(financeNotifierProvider.notifier).updateAccount(
                      acc.id,
                      name: nameCtrl.text.trim(),
                      type: selectedType,
                      bank: bankCtrl.text.trim().isEmpty ? null : bankCtrl.text.trim(),
                      accountNumberLast4: newLast4 ?? (last4Ctrl.text.trim().isEmpty ? null : last4Ctrl.text.trim()),
                      openingBalance: opening,
                      encAccountNumber: encNum,
                      encIfsc: encIfsc,
                    );
                    navigator.pop();
                  },
                  child: const Text('Save Changes'),
                )),
              ]),
            ),
          ),
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
