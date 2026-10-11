import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/models.dart';
import '../../../core/services/smart_entry/capture_inbox.dart';
import '../../../core/services/smart_entry/entry_suggestions.dart';
import '../../../core/services/smart_entry/ai_transaction_service.dart';
import '../../../core/services/smart_entry/parsed_transaction.dart';
import '../../../core/services/smart_entry/quick_templates.dart';
import 'log_salary_modal.dart';
import 'smart_entry_bar.dart';
import '../../splits/presentation/split_expense_modal.dart';

/// What Quick Add should kick off as soon as it opens (widget / shortcut /
/// tile entry points).
enum QuickAddStart { none, voice, scan }


/// Parses the Amount field: a plain number ("120.5"), or a single binary
/// arithmetic expression between exactly two numbers ("100/3", "45+10.5",
/// "500-125", "20*3") — one operator, no chains, no parentheses. Covers the
/// common "split this 3 ways" / "add the tip" case without turning the field
/// into a full calculator. Returns null for anything else (including a
/// division by zero), same as an invalid plain number would.
double? parseAmountExpression(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final direct = double.tryParse(text);
  if (direct != null) return direct;

  final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*([+\-x×*/])\s*(-?\d+(?:\.\d+)?)$').firstMatch(text);
  if (match == null) return null;
  final a = double.parse(match.group(1)!);
  final b = double.parse(match.group(3)!);
  switch (match.group(2)!) {
    case '+':
      return a + b;
    case '-':
      return a - b;
    case 'x':
    case '×':
    case '*':
      return a * b;
    case '/':
      return b == 0 ? null : a / b;
    default:
      return null;
  }
}

class QuickAddModal extends ConsumerStatefulWidget {
  final TransactionModel? existing;
  final TransactionType? initialType;
  final String? initialCreditCardId;
  final String? initialLoanId;

  /// Pre-fill from a smart-entry draft (review inbox, shared text…).
  final ParsedTransaction? initialDraft;

  /// Review-inbox item this entry confirms — removed from the inbox on save.
  final String? captureId;

  /// Text to run through the smart parser as soon as the sheet opens.
  final String? initialSmartText;
  final CaptureSource initialSmartSource;

  /// Image (receipt / screenshot) to OCR as soon as the sheet opens.
  final String? initialImagePath;
  final QuickAddStart startWith;

  const QuickAddModal({
    super.key,
    this.existing,
    this.initialType,
    this.initialCreditCardId,
    this.initialLoanId,
    this.initialDraft,
    this.captureId,
    this.initialSmartText,
    this.initialSmartSource = CaptureSource.typed,
    this.initialImagePath,
    this.startWith = QuickAddStart.none,
  });

  static Future<void> show(
    BuildContext context, {
    TransactionModel? existing,
    TransactionType? initialType,
    String? initialCreditCardId,
    String? initialLoanId,
    ParsedTransaction? initialDraft,
    String? captureId,
    String? initialSmartText,
    CaptureSource initialSmartSource = CaptureSource.typed,
    String? initialImagePath,
    QuickAddStart startWith = QuickAddStart.none,
  }) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => QuickAddModal(
        existing: existing,
        initialType: initialType,
        initialCreditCardId: initialCreditCardId,
        initialLoanId: initialLoanId,
        initialDraft: initialDraft,
        captureId: captureId,
        initialSmartText: initialSmartText,
        initialSmartSource: initialSmartSource,
        initialImagePath: initialImagePath,
        startWith: startWith,
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
  // Guards against a double-tap on Save firing two overlapping
  // addTransaction/updateTransaction calls before the sheet closes — without
  // this a fast double-tap posts the same transaction twice.
  bool _isSaving = false;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  late DateTime _selectedDate;

  String? _selectedAccountId;
  String? _selectedToAccountId;
  String? _selectedCategoryId;
  String? _selectedCardId;
  String? _selectedLoanId;
  // Debit or credit card used as the payment instrument for an expense. A
  // debit card books the spend against its linked bank account (not a
  // separate card outstanding) and locks "From Account" to it; a credit card
  // charges the card's outstanding balance directly and touches no account.
  String? _selectedPayCardId;

  bool get _isEditing => widget.existing != null;

  // Fields the user changed by hand — smart defaults never overwrite these.
  bool _accountTouched = false;
  bool _categoryTouched = false;
  bool _payTouched = false;
  bool _aiAvailable = false;
  String? _filledHint;
  final _smartBarKey = GlobalKey<SmartEntryBarState>();

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
    _selectedPayCardId =
        (existing != null && existing.type == TransactionType.expense) ? existing.creditCardId : null;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(existing.amount.truncateToDouble() == existing.amount ? 0 : 2);
      _merchantController.text = existing.merchant ?? '';
      _notesController.text = existing.description ?? '';
      return;
    }

    // New entry: start from how the user last logged this type.
    if (widget.initialCreditCardId == null && widget.initialLoanId == null) {
      _applyLastDefaults(_selectedType);
    }
    if (widget.initialDraft != null) _applyDraft(widget.initialDraft!, announce: false, rebuild: false);

    AiTransactionService.isUsable().then((v) {
      if (mounted && v != _aiAvailable) setState(() => _aiAvailable = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bar = _smartBarKey.currentState;
      if (bar == null) return;
      if (widget.initialImagePath != null) {
        bar.scanImagePath(widget.initialImagePath!);
      } else if (widget.initialSmartText != null) {
        bar.parseExternal(widget.initialSmartText!, widget.initialSmartSource);
      } else if (widget.startWith == QuickAddStart.voice) {
        bar.startVoice();
      } else if (widget.startWith == QuickAddStart.scan) {
        bar.startScan();
      }
    });
  }

  EntrySuggestions get _suggestions => EntrySuggestions(ref.read(financeNotifierProvider));

  /// Account / pay-with / category from the most recent transaction of [type].
  void _applyLastDefaults(TransactionType type) {
    final last = _suggestions.lastOfType(type);
    if (last == null) return;
    if (!_accountTouched) _selectedAccountId = last.accountId;
    if (!_categoryTouched && last.categoryId != null) _selectedCategoryId = last.categoryId;
    if (!_payTouched && type == TransactionType.expense) _selectedPayCardId = EntrySuggestions.payCardOf(last);
  }

  /// Fills untouched fields from the user's history with [merchant].
  void _applyMerchantMemory(String merchant) {
    final mem = _suggestions.forMerchant(merchant);
    if (mem == null) return;
    setState(() {
      if (!_categoryTouched && mem.categoryId != null && mem.type == _selectedType) _selectedCategoryId = mem.categoryId;
      if (!_accountTouched && mem.accountId != null) _selectedAccountId = mem.accountId;
      if (!_payTouched && _selectedType == TransactionType.expense && mem.type == TransactionType.expense) {
        _selectedPayCardId = mem.payCardId;
      }
    });
  }

  String _fmtAmount(double a) => a.toStringAsFixed(a.truncateToDouble() == a ? 0 : 2);

  /// Pre-fills the form from a smart-entry draft. Only fields the draft
  /// actually found are written; explicit values in the draft win over
  /// remembered defaults.
  void _applyDraft(ParsedTransaction d, {bool announce = true, bool usedAi = false, bool rebuild = true}) {
    void apply() {
      if (d.type == TransactionType.income || d.type == TransactionType.expense) {
        if (d.type != _selectedType) {
          _selectedType = d.type!;
          _applyLastDefaults(_selectedType);
        }
      }
      if (d.amount != null && d.amount! > 0) _amountController.text = _fmtAmount(d.amount!);
      if (d.merchant != null && d.merchant!.isNotEmpty) {
        _merchantController.text = d.merchant!;
        final mem = _suggestions.forMerchant(d.merchant!);
        if (mem != null) {
          if (!_categoryTouched && mem.categoryId != null && mem.type == _selectedType) _selectedCategoryId = mem.categoryId;
          if (!_accountTouched && mem.accountId != null) _selectedAccountId = mem.accountId;
          if (!_payTouched && _selectedType == TransactionType.expense) _selectedPayCardId = mem.payCardId;
        }
      }
      if (d.categoryId != null) _selectedCategoryId = d.categoryId;
      if (d.accountId != null) _selectedAccountId = d.accountId;
      if (d.payCardId != null && _selectedType == TransactionType.expense) _selectedPayCardId = d.payCardId;
      if (d.date != null) _selectedDate = d.date!;
      if (d.notes != null && d.notes!.isNotEmpty && _notesController.text.isEmpty) _notesController.text = d.notes!;
      if (announce) {
        final bits = <String>[
          if (d.amount != null) CurrencyFormatter.format(d.amount!, showDecimals: d.amount! != d.amount!.truncateToDouble()),
          if (d.merchant != null) d.merchant!,
          if (d.date != null) DateFormatter.formatShort(d.date!),
        ];
        _filledHint = '${usedAi ? '✨ AI filled' : 'Filled'}: ${bits.join(' · ')} — check & save';
      }
    }

    rebuild ? setState(apply) : apply();
  }

  void _applyTemplate(QuickTemplate t) {
    setState(() {
      if (t.type != _selectedType) _selectedType = t.type;
      if (t.amount != null) _amountController.text = _fmtAmount(t.amount!);
      _merchantController.text = t.merchant ?? '';
      if (t.categoryId != null) {
        _selectedCategoryId = t.categoryId;
        _categoryTouched = true;
      }
      if (t.accountId != null) {
        _selectedAccountId = t.accountId;
        _accountTouched = true;
      }
      if (t.type == TransactionType.expense) {
        _selectedPayCardId = t.payCardId;
        _payTouched = true;
      }
      _filledHint = 'Template "${t.label}" applied — check & save';
    });
  }

  void _applyCombo(MerchantMemory m) {
    setState(() {
      if (m.type != _selectedType) _selectedType = m.type;
      _amountController.text = _fmtAmount(m.lastAmount);
      _merchantController.text = m.merchant;
      if (m.categoryId != null) _selectedCategoryId = m.categoryId;
      if (m.accountId != null) _selectedAccountId = m.accountId;
      if (m.type == TransactionType.expense) _selectedPayCardId = m.payCardId;
      _filledHint = null;
    });
  }

  Future<void> _saveAsTemplate() async {
    final amount = parseAmountExpression(_amountController.text.trim());
    final merchant = _merchantController.text.trim();
    final defaultLabel = [
      if (merchant.isNotEmpty) merchant,
      if (amount != null) CurrencyFormatter.format(amount),
    ].join(' ');
    final ctrl = TextEditingController(text: defaultLabel.isEmpty ? _selectedType.displayName : defaultLabel);
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Save as one-tap template', style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Chip label')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    await ref.read(quickTemplatesProvider.notifier).add(
          label: label,
          type: _selectedType,
          amount: amount,
          merchant: merchant.isEmpty ? null : merchant,
          categoryId: _selectedCategoryId,
          accountId: _selectedAccountId,
          payCardId: _selectedType == TransactionType.expense ? _selectedPayCardId : null,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Template "$label" saved — it shows at the top of Quick Add'), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildShortcutChips(FinanceState financeState) {
    final templates = ref.watch(quickTemplatesProvider);
    final combos = EntrySuggestions(financeState).frequentCombos(limit: 5).where((c) {
      // Don't repeat a combo the user already pinned as a template.
      return !templates.any((t) => (t.merchant ?? '').toLowerCase() == c.merchant.toLowerCase() && t.amount == c.lastAmount);
    }).toList();
    if (templates.isEmpty && combos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final t in templates)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: Text('Remove "${t.label}"?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remove', style: TextStyle(color: AppColors.expense))),
                      ],
                    ),
                  );
                  if (ok == true) ref.read(quickTemplatesProvider.notifier).remove(t.id);
                },
                child: ActionChip(
                  avatar: Icon(LucideIcons.star, size: 13, color: AppColors.warning),
                  label: Text(t.label, style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                  backgroundColor: AppColors.surfaceLight,
                  side: BorderSide(color: AppColors.border),
                  onPressed: () => _applyTemplate(t),
                ),
              ),
            ),
          for (final c in combos)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: Icon(LucideIcons.history, size: 13, color: AppColors.textMuted),
                label: Text('${c.merchant} ${CurrencyFormatter.format(c.lastAmount)}', style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                backgroundColor: AppColors.surfaceLight,
                side: BorderSide(color: AppColors.border),
                onPressed: () => _applyCombo(c),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildMerchantSuggestions() {
    final q = _merchantController.text.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    final matches = _suggestions.matchMerchants(q, type: _selectedType).where((m) => m.toLowerCase() != q.toLowerCase()).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final m in matches)
            ActionChip(
              label: Text(m, style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surfaceLight,
              side: BorderSide(color: AppColors.border),
              onPressed: () {
                _merchantController.text = m;
                _merchantController.selection = TextSelection.collapsed(offset: m.length);
                _applyMerchantMemory(m);
              },
            ),
        ],
      ),
    );
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
    // Cards selectable as the payment instrument for an expense — debit
    // (deducts from its linked account) and credit (charges the card's
    // outstanding balance). Prepaid/forex cards aren't wired for either.
    final payCards = creditCards.where((c) => c.cardType == CardType.debit || c.cardType == CardType.credit).toList();
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

    // Resolve the chosen pay card (expense only). A debit card with a valid
    // linked account locks "From Account" to it; a credit card charges the
    // card directly and needs no bank account at all.
    CardModel? selectedPayCard;
    if (_selectedType == TransactionType.expense && _selectedPayCardId != null) {
      for (final c in payCards) {
        if (c.id == _selectedPayCardId) {
          selectedPayCard = c;
          break;
        }
      }
    }
    final isCashPay = _selectedPayCardId == kCashPaySentinel;
    if (selectedPayCard == null && !isCashPay) _selectedPayCardId = null;
    final isCreditCharge = selectedPayCard?.cardType == CardType.credit;
    AccountModel? debitLinkedAccount;
    if (selectedPayCard?.cardType == CardType.debit && selectedPayCard!.linkedAccountId != null) {
      for (final a in accounts) {
        if (a.id == selectedPayCard.linkedAccountId) {
          debitLinkedAccount = a;
          break;
        }
      }
      if (debitLinkedAccount != null) _selectedAccountId = debitLinkedAccount.id;
    }
    // The account/pay-card can be changed even while editing — balances are
    // always recomputed from transaction history (or, for a card charge,
    // reversed off the old card and applied to the new one in
    // updateTransaction), so moving a transaction is always safe.
    final accountLocked = debitLinkedAccount != null || isCreditCharge || isCashPay;

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
            if (!_isEditing) ...[
              SmartEntryBar(
                key: _smartBarKey,
                aiAvailable: _aiAvailable,
                onParsed: (d, {required usedAi, required source}) => _applyDraft(d, usedAi: usedAi),
              ),
              _buildShortcutChips(financeState),
              if (_filledHint != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(LucideIcons.checkCircle2, size: 14, color: AppColors.income),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_filledHint!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                ]),
              ],
            ],
            if (_isEditing && financeState.splitExpenses.any((s) => s.transactionId == widget.existing!.id)) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.users, size: 15, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "This bill is split with others. Changing the amount here won't update their shares — manage the split from Splits.",
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
            if (_selectedType == TransactionType.income && !_isEditing) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: Icon(LucideIcons.briefcase, size: 15, color: AppColors.primary),
                  label: Text(
                    'Got a salary credit? Log it with a company & PF breakdown →',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    LogSalaryModal.show(context);
                  },
                ),
              ),
            ],
            if (_selectedType == TransactionType.expense && !_isEditing) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: Icon(LucideIcons.users, size: 15, color: AppColors.primary),
                  label: Text(
                    'Splitting this with others? Track who owes you →',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    SplitExpenseModal.show(context);
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),

            // Amount Input — also accepts a quick "100/3" style split, see
            // parseAmountExpression. A plain numeric keyboard has no room for
            // +-*/ on either platform, so this field uses the text keyboard
            // with everything but digits/operators/decimal filtered out.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.text,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-x×*/. ]'))],
                    autofocus: !_isEditing,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      prefixText: '${CurrencyFormatter.symbol} ',
                      prefixStyle: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.primary),
                      hintText: '0 or 100/3',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  Builder(builder: (context) {
                    final text = _amountController.text.trim();
                    final isPlainNumber = double.tryParse(text) != null;
                    final result = isPlainNumber ? null : parseAmountExpression(text);
                    if (result == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '= ${CurrencyFormatter.symbol} ${result.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    );
                  }),
                ],
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
              onChanged: accountLocked
                  ? null
                  : (val) => setState(() {
                        _selectedAccountId = val;
                        _accountTouched = true;
                      }),
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
            if (isCreditCharge) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.creditCard, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Charged to ${selectedPayCard!.name} — no account balance affected',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
            if (isCashPay) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.banknote, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Paid with cash — no account balance affected',
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

            if (_selectedType == TransactionType.expense) ...[
              Text('Pay With', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                value: _selectedPayCardId,
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
                  ...payCards.map((c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(
                          c.cardType == CardType.credit ? '${c.name} ••${c.last4} (Credit)' : '${c.bank} Debit ••${c.last4}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                  DropdownMenuItem<String?>(
                    value: kCashPaySentinel,
                    child: Text('Cash'),
                  ),
                ],
                onChanged: (val) => setState(() {
                  _selectedPayCardId = val;
                  _payTouched = true;
                }),
              ),
              if (selectedPayCard != null && selectedPayCard.cardType == CardType.debit && debitLinkedAccount == null) ...[
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
                onChanged: (val) => setState(() {
                  _selectedCategoryId = val;
                  _categoryTouched = true;
                }),
              ),
              const SizedBox(height: 14),

              TextField(
                key: const Key('merchant_field'),
                controller: _merchantController,
                textCapitalization: TextCapitalization.words,
                onChanged: (v) {
                  // Exact match of a known merchant → pull its usual
                  // category / account / card into any untouched field.
                  if (!_isEditing) _applyMerchantMemory(v);
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText: _selectedType == TransactionType.income && _selectedCategoryId == 'cat_freelance'
                      ? 'Client / Source (e.g. Acme LLC, Fiverr)'
                      : _selectedType == TransactionType.income
                          ? 'Source / Payer Name (Optional)'
                          : 'Merchant / Payee Name (e.g. Swiggy, Amazon)',
                ),
              ),
              if (!_isEditing) _buildMerchantSuggestions(),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes / Description (Optional)',
              ),
            ),
            if (!_isEditing && (_selectedType == TransactionType.expense || _selectedType == TransactionType.income))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _saveAsTemplate,
                  icon: Icon(LucideIcons.star, size: 14, color: AppColors.warning),
                  label: Text('Save as template', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              )
            else
              const SizedBox(height: 12),
            const SizedBox(height: 12),

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
                onPressed: _isSaving ? null : _saveTransaction,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Save Changes' : 'Save Transaction', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                if (!val) return;
                setState(() {
                  _selectedType = type;
                  _applyLastDefaults(type);
                });
              },
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) return;
    final amountText = _amountController.text.trim();
    final amount = parseAmountExpression(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // Resolve the chosen pay card up front — also on edit now, so switching
    // "Pay With" (or the plain account) on an existing transaction resolves
    // the same way a new one would.
    CardModel? payCard;
    if (_selectedType == TransactionType.expense && _selectedPayCardId != null) {
      final state = ref.read(financeNotifierProvider);
      for (final c in state.creditCards) {
        if (c.id == _selectedPayCardId) {
          payCard = c;
          break;
        }
      }
    }
    final isCreditCharge = payCard?.cardType == CardType.credit;
    final isCashPay = _selectedType == TransactionType.expense && _selectedPayCardId == kCashPaySentinel;

    // Every transaction still needs a real `accountId` — the cloud schema's
    // foreign key requires one, even for a credit-card charge where the
    // account is just a reference and isn't actually debited (see
    // accountsWithCalculatedBalances).
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

    // Pay-card spend: a debit card must be linked to an existing account and
    // the expense is booked against that account. A credit card charges the
    // card's outstanding balance directly — `_selectedAccountId` still rides
    // along as the required `accountId` reference, but `creditCardId` below
    // tells `accountsWithCalculatedBalances` to skip debiting it.
    String effectiveAccountId = _selectedAccountId!;
    String? payCardId;
    if (payCard != null && payCard.cardType == CardType.debit) {
      final linkedId = payCard.linkedAccountId;
      final state = ref.read(financeNotifierProvider);
      final linkOk = linkedId != null && state.accounts.any((a) => a.id == linkedId && !a.isDeleted);
      if (!linkOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link this card to an account first'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      effectiveAccountId = linkedId;
      payCardId = payCard.id;
    } else if (isCreditCharge) {
      payCardId = payCard!.id;
    }

    final notifier = ref.read(financeNotifierProvider.notifier);
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await notifier.updateTransaction(
          widget.existing!.id,
          amount: amount,
          categoryId: _selectedCategoryId,
          merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
          date: _selectedDate,
          description: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          accountId: effectiveAccountId,
          // Only expense transactions have a "Pay With" card to reconsider —
          // for every other type (income/transfer/creditCardPayment/
          // loanPayment) `payCardId` is always null here, and passing
          // clearCreditCardId along with it would wrongly wipe out a
          // creditCardPayment's target card or a loanPayment's link. Leaving
          // both un-set for those types keeps updateTransaction's "not
          // supplied = unchanged" default.
          creditCardId: _selectedType == TransactionType.expense ? payCardId : null,
          clearCreditCardId: _selectedType == TransactionType.expense && payCardId == null,
          isCashSpend: _selectedType == TransactionType.expense ? isCashPay : null,
        );
      } else {
        await notifier.addTransaction(
          accountId: effectiveAccountId,
          toAccountId: _selectedType == TransactionType.transfer ? _selectedToAccountId : null,
          type: _selectedType,
          amount: amount,
          categoryId: _selectedCategoryId,
          merchant: _merchantController.text.trim().isNotEmpty ? _merchantController.text.trim() : null,
          date: _selectedDate,
          description: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          creditCardId: _selectedType == TransactionType.creditCardPayment ? _selectedCardId : payCardId,
          loanId: _selectedType == TransactionType.loanPayment ? _selectedLoanId : null,
          isCashSpend: isCashPay,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save transaction: $e'), backgroundColor: AppColors.expense, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (widget.captureId != null) {
      await ref.read(captureInboxProvider.notifier).markLogged(widget.captureId!);
    }
    if (!mounted) return;
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
