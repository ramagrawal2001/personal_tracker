import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/models.dart';

class QuickAddModal extends ConsumerStatefulWidget {
  final TransactionModel? existing;
  final TransactionType? initialType;
  final String? initialCreditCardId;
  final String? initialLoanId;

  const QuickAddModal({
    super.key,
    this.existing,
    this.initialType,
    this.initialCreditCardId,
    this.initialLoanId,
  });

  static Future<void> show(
    BuildContext context, {
    TransactionModel? existing,
    TransactionType? initialType,
    String? initialCreditCardId,
    String? initialLoanId,
  }) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => QuickAddModal(
        existing: existing,
        initialType: initialType,
        initialCreditCardId: initialCreditCardId,
        initialLoanId: initialLoanId,
      ),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  ConsumerState<QuickAddModal> createState() => _QuickAddModalState();
}

class _QuickAddModalState extends ConsumerState<QuickAddModal> {
  late TransactionType _selectedType;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  late DateTime _selectedDate;

  String? _selectedAccountId;
  String? _selectedToAccountId;
  String? _selectedCategoryId;
  String? _selectedCardId;
  String? _selectedLoanId;
  // Debit card used as the payment instrument for an expense. When set, the
  // spend is booked against the card's linked bank account (not a separate
  // card outstanding) and the "From Account" picker is locked to it.
  String? _selectedDebitCardId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedType = existing?.type ?? widget.initialType ?? TransactionType.expense;
    _selectedDate = existing?.date ?? DateTime.now();
    _selectedAccountId = existing?.accountId;
    _selectedToAccountId = existing?.toAccountId;
    _selectedCategoryId = existing?.categoryId;
    _selectedCardId = existing?.creditCardId ?? widget.initialCreditCardId;
    _selectedLoanId = existing?.loanId ?? widget.initialLoanId;
    _selectedDebitCardId =
        (existing != null && existing.type == TransactionType.expense) ? existing.creditCardId : null;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(existing.amount.truncateToDouble() == existing.amount ? 0 : 2);
      _merchantController.text = existing.merchant ?? '';
      _notesController.text = existing.description ?? '';
    }
  }

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
    final debitCards = creditCards.where((c) => c.cardType == CardType.debit).toList();
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

    // Resolve the chosen debit card (expense only). When it has a valid linked
    // account, lock "From Account" to that account so the spend deducts from it.
    CardModel? selectedDebitCard;
    if (_selectedType == TransactionType.expense && _selectedDebitCardId != null) {
      for (final c in debitCards) {
        if (c.id == _selectedDebitCardId) {
          selectedDebitCard = c;
          break;
        }
      }
    }
    if (selectedDebitCard == null) _selectedDebitCardId = null;
    AccountModel? debitLinkedAccount;
    if (selectedDebitCard?.linkedAccountId != null) {
      for (final a in accounts) {
        if (a.id == selectedDebitCard!.linkedAccountId) {
          debitLinkedAccount = a;
          break;
        }
      }
      if (debitLinkedAccount != null) _selectedAccountId = debitLinkedAccount.id;
    }
    final accountLocked = _isEditing || debitLinkedAccount != null;

    final horizontalPadding = context.responsiveHorizontalPadding(mobile: 16, tablet: 24, desktop: 32);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: bottomInset + context.responsivePadding(mobile: 24, tablet: 32, desktop: 40),
          left: horizontalPadding,
          right: horizontalPadding,
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
                  _isEditing ? 'Edit Transaction' : 'Log Transaction',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Type Selector Chips (locked while editing — changing type would
            // require re-deriving balance/outstanding effects; delete + recreate instead)
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
            const SizedBox(height: 18),

            // Amount Input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: !_isEditing,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  prefixText: '${CurrencyFormatter.symbol} ',
                  prefixStyle: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.primary),
                  hintText: '0',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date picker
            Text('Date', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Text(DateFormatter.formatShort(_selectedDate), style: TextStyle(color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Source Account Selector (locked while editing)
            Text('From Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _selectedAccountId,
              dropdownColor: AppColors.surface,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
              ),
              items: accounts.map((acc) {
                return DropdownMenuItem(
                  value: acc.id,
                  child: Text('${acc.name} (${CurrencyFormatter.format(acc.calculatedBalance)})'),
                );
              }).toList(),
              onChanged: accountLocked ? null : (val) => setState(() => _selectedAccountId = val),
            ),
            if (debitLinkedAccount != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.arrowDownCircle, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Deducts from ${debitLinkedAccount.name}',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),

            // Destination / Specific Selectors based on Type
            if (_selectedType == TransactionType.transfer) ...[
              Text('To Destination Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedToAccountId,
                dropdownColor: AppColors.surface,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                ),
                items: filteredToAccounts.map((acc) {
                  return DropdownMenuItem(
                    value: acc.id,
                    child: Text('${acc.name} (${CurrencyFormatter.format(acc.calculatedBalance)})'),
                  );
                }).toList(),
                onChanged: _isEditing ? null : (val) => setState(() => _selectedToAccountId = val),
              ),
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.creditCardPayment) ...[
              Text('Target Credit Card', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedCardId,
                dropdownColor: AppColors.surface,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                ),
                items: creditCards.map((card) {
                  return DropdownMenuItem(
                    value: card.id,
                    child: Text('${card.name} (Due: ${CurrencyFormatter.format(card.currentOutstanding)})'),
                  );
                }).toList(),
                onChanged: _isEditing ? null : (val) => setState(() => _selectedCardId = val),
              ),
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.loanPayment) ...[
              Text('Target Loan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedLoanId,
                dropdownColor: AppColors.surface,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                ),
                items: loans.map((loan) {
                  return DropdownMenuItem(
                    value: loan.id,
                    child: Text('${loan.name} (Outstanding: ${CurrencyFormatter.format(loan.outstandingAmount)})'),
                  );
                }).toList(),
                onChanged: _isEditing ? null : (val) => setState(() => _selectedLoanId = val),
              ),
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.expense && debitCards.isNotEmpty) ...[
              Text('Pay With', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                value: _selectedDebitCardId,
                dropdownColor: AppColors.surface,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Bank account (default)'),
                  ),
                  ...debitCards.map((c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text('${c.bank} Debit ••${c.last4}', overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: _isEditing ? null : (val) => setState(() => _selectedDebitCardId = val),
              ),
              if (selectedDebitCard != null && debitLinkedAccount == null) ...[
                const SizedBox(height: 6),
                Text(
                  'Link this card to an account first (Cards → edit this card).',
                  style: TextStyle(fontSize: 12, color: AppColors.expense),
                ),
              ],
              const SizedBox(height: 14),
            ],

            if (_selectedType == TransactionType.expense || _selectedType == TransactionType.income) ...[
              Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedCategoryId,
                dropdownColor: AppColors.surface,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                ),
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
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveTransaction,
                child: Text(_isEditing ? 'Save Changes' : 'Save Transaction', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildTypeChip(TransactionType type, String label, Color color) {
    final isSelected = _selectedType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        selectedColor: color.withValues(alpha: 0.2),
        backgroundColor: AppColors.surfaceLight,
        side: BorderSide(color: isSelected ? color : AppColors.border),
        labelStyle: TextStyle(
          color: isSelected ? color : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
        tooltip: 'Select transaction type: $label',
        onSelected: _isEditing
            ? null
            : (val) {
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
        const SnackBar(content: Text('Please enter a valid amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (_selectedType == TransactionType.transfer && _selectedToAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination account'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_selectedType == TransactionType.creditCardPayment && _selectedCardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a credit card'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_selectedType == TransactionType.loanPayment && _selectedLoanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a loan'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // Debit-card spend: the card must be linked to an existing account, and the
    // expense is booked against that account.
    String effectiveAccountId = _selectedAccountId!;
    String? debitCardId;
    if (_selectedType == TransactionType.expense && _selectedDebitCardId != null && !_isEditing) {
      final state = ref.read(financeNotifierProvider);
      CardModel? card;
      for (final c in state.creditCards) {
        if (c.id == _selectedDebitCardId) {
          card = c;
          break;
        }
      }
      final linkedId = card?.linkedAccountId;
      final linkOk = linkedId != null && state.accounts.any((a) => a.id == linkedId && !a.isDeleted);
      if (!linkOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link this card to an account first'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      effectiveAccountId = linkedId;
      debitCardId = card!.id;
    }

    final notifier = ref.read(financeNotifierProvider.notifier);
    if (_isEditing) {
      notifier.updateTransaction(
        widget.existing!.id,
        amount: amount,
        categoryId: _selectedCategoryId,
        merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
        date: _selectedDate,
        description: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );
    } else {
      notifier.addTransaction(
        accountId: effectiveAccountId,
        toAccountId: _selectedType == TransactionType.transfer ? _selectedToAccountId : null,
        type: _selectedType,
        amount: amount,
        categoryId: _selectedCategoryId,
        merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
        date: _selectedDate,
        description: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        creditCardId: _selectedType == TransactionType.creditCardPayment ? _selectedCardId : debitCardId,
        loanId: _selectedType == TransactionType.loanPayment ? _selectedLoanId : null,
      );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing ? 'Transaction updated!' : 'Transaction saved successfully!'),
        backgroundColor: AppColors.income,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
