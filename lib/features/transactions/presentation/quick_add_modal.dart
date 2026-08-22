import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';

class QuickAddModal extends ConsumerStatefulWidget {
  const QuickAddModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const QuickAddModal(),
    );
  }

  @override
  ConsumerState<QuickAddModal> createState() => _QuickAddModalState();
}

class _QuickAddModalState extends ConsumerState<QuickAddModal> {
  TransactionType _selectedType = TransactionType.expense;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String? _selectedAccountId;
  String? _selectedToAccountId;
  String? _selectedCategoryId;
  String? _selectedCardId;
  String? _selectedLoanId;

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final accounts = financeState.accountsWithCalculatedBalances;
    final categories = financeState.categories;
    final creditCards = financeState.creditCards;
    final loans = financeState.loans;

    final filteredCategories = categories
        .where((c) => _selectedType == TransactionType.expense ? c.type == 'expense' : c.type == 'income')
        .toList();

    if (!accounts.any((a) => a.id == _selectedAccountId)) {
      _selectedAccountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
    final filteredToAccounts = accounts.where((a) => a.id != _selectedAccountId).toList();
    if (!filteredToAccounts.any((a) => a.id == _selectedToAccountId)) {
      _selectedToAccountId = filteredToAccounts.isNotEmpty ? filteredToAccounts.first.id : null;
    }
    if (!filteredCategories.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = filteredCategories.isNotEmpty ? filteredCategories.first.id : null;
    }
    if (!creditCards.any((c) => c.id == _selectedCardId)) {
      _selectedCardId = creditCards.isNotEmpty ? creditCards.first.id : null;
    }
    if (!loans.any((l) => l.id == _selectedLoanId)) {
      _selectedLoanId = loans.isNotEmpty ? loans.first.id : null;
    }


    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header & Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Log Transaction',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Type Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTypeChip(TransactionType.expense, 'Expense', AppColors.expense),
                  _buildTypeChip(TransactionType.income, 'Income', AppColors.income),
                  _buildTypeChip(TransactionType.transfer, 'Transfer', AppColors.transfer),
                  _buildTypeChip(TransactionType.creditCardPayment, 'Card Pay', AppColors.creditCard),
                  _buildTypeChip(TransactionType.loanPayment, 'Loan EMI', AppColors.loan),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Amount Input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
                  hintText: '0',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Source Account Selector
            const Text('From Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedAccountId,
              dropdownColor: AppColors.surface,
              items: accounts.map((acc) {
                return DropdownMenuItem(
                  value: acc.id,
                  child: Text('${acc.name} (${CurrencyFormatter.format(acc.calculatedBalance)})'),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedAccountId = val),
            ),
            const SizedBox(height: 14),

            // Destination / Specific Selectors based on Type
            if (_selectedType == TransactionType.transfer) ...[
              const Text('To Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedToAccountId,
                dropdownColor: AppColors.surface,
                items: filteredToAccounts.map((acc) {
                  return DropdownMenuItem(
                    value: acc.id,
                    child: Text('${acc.name} (${CurrencyFormatter.format(acc.calculatedBalance)})'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedToAccountId = val),
              ),
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.creditCardPayment) ...[
              const Text('Target Credit Card', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedCardId,
                dropdownColor: AppColors.surface,
                items: creditCards.map((card) {
                  return DropdownMenuItem(
                    value: card.id,
                    child: Text('${card.name} (Due: ${CurrencyFormatter.format(card.currentOutstanding)})'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCardId = val),
              ),
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.loanPayment) ...[
              const Text('Target Loan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedLoanId,
                dropdownColor: AppColors.surface,
                items: loans.map((loan) {
                  return DropdownMenuItem(
                    value: loan.id,
                    child: Text('${loan.name} (Outstanding: ${CurrencyFormatter.format(loan.outstandingAmount)})'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedLoanId = val),
              ),
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.expense || _selectedType == TransactionType.income) ...[
              const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedCategoryId,
                dropdownColor: AppColors.surface,
                items: filteredCategories.map((cat) {
                  return DropdownMenuItem(
                    value: cat.id,
                    child: Text(cat.name),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCategoryId = val),
              ),
              const SizedBox(height: 14),


              TextField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  labelText: 'Merchant / Payee Name (e.g. Swiggy, Amazon)',
                ),
              ),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes / Description (Optional)',
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveTransaction,
                child: const Text('Save Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(TransactionType type, String label, Color color) {
    final isSelected = _selectedType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: color.withValues(alpha: 0.2),
        backgroundColor: AppColors.surfaceLight,
        side: BorderSide(color: isSelected ? color : AppColors.border),
        labelStyle: TextStyle(
          color: isSelected ? color : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (val) {
          if (val) setState(() => _selectedType = type);
        },
      ),
    );
  }

  void _saveTransaction() {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account')),
      );
      return;
    }

    ref.read(financeNotifierProvider.notifier).addTransaction(
          accountId: _selectedAccountId!,
          toAccountId: _selectedType == TransactionType.transfer ? _selectedToAccountId : null,
          type: _selectedType,
          amount: amount,
          categoryId: _selectedCategoryId,
          merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
          date: DateTime.now(),
          description: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          creditCardId: _selectedType == TransactionType.creditCardPayment ? _selectedCardId : null,
          loanId: _selectedType == TransactionType.loanPayment ? _selectedLoanId : null,
        );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaction saved successfully!'),
        backgroundColor: AppColors.income,
      ),
    );
  }
}
