import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/secret_cipher_service.dart';
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
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();

  AccountType _selectedType = AccountType.savingsAccount;

  @override
  void dispose() {
    _nameController.dispose();
    _bankController.dispose();
    _last4Controller.dispose();
    _openingBalanceController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
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
            const SizedBox(height: 18),
            Row(children: [
              Icon(LucideIcons.lock, size: 13, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Sensitive details (encrypted on this device)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _accountNumberController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Full Account Number',
                prefixIcon: Icon(LucideIcons.hash, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ifscController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'IFSC / Routing Number',
                prefixIcon: Icon(LucideIcons.landmark, size: 18),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
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

  Future<void> _saveAccount() async {
    final name = _nameController.text.trim();
    final openingBalanceText = _openingBalanceController.text.trim();
    final openingBalance = double.tryParse(openingBalanceText) ?? 0.0;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please enter an account name'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final rawNumber = _accountNumberController.text.replaceAll(RegExp(r'\D'), '');
    final ifsc = _ifscController.text.trim().toUpperCase();
    var last4 = _last4Controller.text.trim();
    if (rawNumber.length >= 4) last4 = rawNumber.substring(rawNumber.length - 4);

    String? encAccountNumber, encIfsc;
    if (rawNumber.isNotEmpty || ifsc.isNotEmpty) {
      final cipher = ref.read(secretCipherServiceProvider);
      if (!cipher.isReady) await cipher.restoreFromCache();
      if (cipher.isReady) {
        if (rawNumber.isNotEmpty) encAccountNumber = cipher.encryptField(rawNumber);
        if (ifsc.isNotEmpty) encIfsc = cipher.encryptField(ifsc);
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Secure storage is locked — account saved without encrypted details'), backgroundColor: AppColors.warning, behavior: SnackBarBehavior.floating),
        );
      }
    }

    ref.read(financeNotifierProvider.notifier).addAccount(
          name: name,
          type: _selectedType,
          bank: _bankController.text.trim().isNotEmpty ? _bankController.text.trim() : null,
          accountNumberLast4: last4.isNotEmpty ? last4 : null,
          openingBalance: openingBalance,
          encAccountNumber: encAccountNumber,
          encIfsc: encIfsc,
        );

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Account created successfully!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}
