import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/responsive.dart';

class AddAccountModal extends ConsumerStatefulWidget {
  const AddAccountModal({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const AddAccountModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  ConsumerState<AddAccountModal> createState() => _AddAccountModalState();
}

class _AddAccountModalState extends ConsumerState<AddAccountModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bankController = TextEditingController();
  final TextEditingController _last4Controller = TextEditingController();
  final TextEditingController _openingBalanceController = TextEditingController();

  AccountType _selectedType = AccountType.savingsAccount;

  @override
  void dispose() {
    _nameController.dispose();
    _bankController.dispose();
    _last4Controller.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 12,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add New Account',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Account Name (e.g. HDFC Salary Acc)',
                prefixIcon: Icon(LucideIcons.wallet, size: 18),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<AccountType>(
              isExpanded: true,
              value: _selectedType,
              dropdownColor: AppColors.surface,
              decoration: const InputDecoration(
                labelText: 'Account Type',
                prefixIcon: Icon(LucideIcons.landmark, size: 18),
              ),
              items: AccountType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedType = val);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bankController,
                    decoration: const InputDecoration(
                      labelText: 'Bank Name',
                      prefixIcon: Icon(LucideIcons.building, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _last4Controller,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Last 4 Digits',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _openingBalanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Opening Balance (${CurrencyFormatter.symbol})',
                hintText: '50000',
                prefixText: '${CurrencyFormatter.symbol} ',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveAccount,
                child: const Text('Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveAccount() {
    final name = _nameController.text.trim();
    final openingBalanceText = _openingBalanceController.text.trim();
    final openingBalance = double.tryParse(openingBalanceText) ?? 0.0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an account name'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    ref.read(financeNotifierProvider.notifier).addAccount(
          name: name,
          type: _selectedType,
          bank: _bankController.text.trim().isNotEmpty ? _bankController.text.trim() : null,
          accountNumberLast4: _last4Controller.text.trim().isNotEmpty ? _last4Controller.text.trim() : null,
          openingBalance: openingBalance,
        );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Account created successfully!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}
