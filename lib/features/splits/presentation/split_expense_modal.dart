import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/models.dart';

/// Resolves each participant's owed share for a split, given [mode] and the
/// raw values entered for them (interpretation depends on mode) plus the
/// payer's own raw input (only meaningful for ratio/percentage). Returns
/// null when the inputs don't resolve to something valid — the caller shows
/// a mode-specific validation message rather than this function's reason.
///
/// The payer's own share is never part of the returned map — it's always
/// `totalAmount - sum(returned shares)`, computed by the caller.
Map<String, double>? resolveSplitShares({
  required SplitMode mode,
  required double totalAmount,
  required List<String> participantIds,
  required Map<String, double> participantInputs,
  double payerInput = 1,
}) {
  if (participantIds.isEmpty || totalAmount <= 0) return null;
  switch (mode) {
    case SplitMode.equal:
      final each = double.parse((totalAmount / (participantIds.length + 1)).toStringAsFixed(2));
      return {for (final id in participantIds) id: each};

    case SplitMode.custom:
      final sum = participantIds.fold(0.0, (s, id) => s + (participantInputs[id] ?? 0));
      if (sum <= 0 || sum > totalAmount + 0.01) return null;
      return {for (final id in participantIds) id: participantInputs[id] ?? 0};

    case SplitMode.ratio:
      final ratioSum = payerInput + participantIds.fold(0.0, (s, id) => s + (participantInputs[id] ?? 0));
      if (ratioSum <= 0) return null;
      return {
        for (final id in participantIds)
          id: double.parse((totalAmount * (participantInputs[id] ?? 0) / ratioSum).toStringAsFixed(2)),
      };

    case SplitMode.percentage:
      final pctSum = payerInput + participantIds.fold(0.0, (s, id) => s + (participantInputs[id] ?? 0));
      if ((pctSum - 100).abs() > 0.5) return null;
      return {
        for (final id in participantIds)
          id: double.parse((totalAmount * (participantInputs[id] ?? 0) / 100).toStringAsFixed(2)),
      };
  }
}

/// Logs a split expense: the *full* bill as a real expense (so the paying
/// account/card matches the actual bank statement), plus who owes what back
/// — tracked even if they never open the app. See
/// FinanceNotifier.addSplitExpense.
class SplitExpenseModal extends ConsumerStatefulWidget {
  const SplitExpenseModal({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const SplitExpenseModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  ConsumerState<SplitExpenseModal> createState() => _SplitExpenseModalState();
}

class _SplitExpenseModalState extends ConsumerState<SplitExpenseModal> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _payerInputController = TextEditingController(text: '1');
  DateTime _selectedDate = DateTime.now();
  String? _accountId;
  String? _creditCardId; // null = pay from _accountId; set = charge this card
  String? _categoryId;
  SplitMode _mode = SplitMode.equal;
  final Set<String> _selectedPersonIds = {};
  final Map<String, TextEditingController> _shareControllers = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _payerInputController.dispose();
    for (final c in _shareControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String personId) =>
      _shareControllers.putIfAbsent(personId, () => TextEditingController());

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final people = financeState.people.where((p) => !p.isDeleted).toList();
    final accounts = financeState.accountsWithCalculatedBalances.where((a) => !a.isDeleted).toList();
    final creditCards = financeState.creditCards.where((c) => !c.isDeleted && c.cardType == CardType.credit).toList();
    final categories = financeState.categories.where((c) => !c.isDeleted && c.type == 'expense').toList();

    if (!accounts.any((a) => a.id == _accountId)) {
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
    if (_creditCardId != null && !creditCards.any((c) => c.id == _creditCardId)) {
      _creditCardId = null;
    }
    if (!categories.any((c) => c.id == _categoryId)) {
      _categoryId = categories.isNotEmpty ? categories.first.id : null;
    }

    final total = double.tryParse(_amountController.text.trim()) ?? 0;
    final participantIds = _selectedPersonIds.toList();
    final payerInput = double.tryParse(_payerInputController.text.trim()) ?? 0;
    final participantInputs = <String, double>{
      for (final id in participantIds) id: double.tryParse(_controllerFor(id).text.trim()) ?? 0,
    };
    final shares = resolveSplitShares(
      mode: _mode,
      totalAmount: total,
      participantIds: participantIds,
      participantInputs: participantInputs,
      payerInput: payerInput,
    );
    final myShare = shares == null ? null : total - shares.values.fold(0.0, (s, v) => s + v);

    final horizontalPadding = context.responsiveHorizontalPadding(mobile: 16, tablet: 24, desktop: 32);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
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
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Icon(LucideIcons.users, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Split an expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The full bill is logged as your real expense — only the unsettled shares are tracked separately.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),

            _field('Title', LucideIcons.receipt, _titleController, hint: 'e.g. Panipuri'),
            const SizedBox(height: 12),
            _field('Total bill amount', LucideIcons.indianRupee, _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),

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
                child: Row(children: [
                  Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Text(DateFormatter.formatShort(_selectedDate), style: TextStyle(color: AppColors.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            if (categories.isNotEmpty) ...[
              _dropdown<String>(
                label: 'Category',
                value: _categoryId,
                items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
            ],

            _dropdown<String>(
              label: 'Paid from account',
              value: _accountId,
              items: accounts
                  .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (${CurrencyFormatter.format(a.calculatedBalance)})')))
                  .toList(),
              onChanged: _creditCardId != null ? null : (v) => setState(() => _accountId = v),
            ),
            if (creditCards.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Bank account'),
                    selected: _creditCardId == null,
                    onSelected: (_) => setState(() => _creditCardId = null),
                  ),
                  ...creditCards.map((c) => ChoiceChip(
                        label: Text('${c.name} (Credit)'),
                        selected: _creditCardId == c.id,
                        onSelected: (_) => setState(() => _creditCardId = c.id),
                      )),
                ],
              ),
            ],
            const SizedBox(height: 16),

            Text('Split', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SplitMode.values.map((m) {
                final selected = _mode == m;
                return ChoiceChip(
                  label: Text(m.displayName),
                  selected: selected,
                  onSelected: (_) => setState(() => _mode = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Text('Split with', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const Spacer(),
                TextButton.icon(
                  icon: Icon(LucideIcons.userPlus, size: 14, color: AppColors.primary),
                  label: Text('Add person', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  onPressed: () => _showQuickAddPerson(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (people.isEmpty)
              Text('No people yet — add one above.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: people.map((p) {
                  final selected = _selectedPersonIds.contains(p.id);
                  return FilterChip(
                    label: Text(p.name),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedPersonIds.add(p.id);
                      } else {
                        _selectedPersonIds.remove(p.id);
                        _shareControllers.remove(p.id)?.dispose();
                      }
                    }),
                  );
                }).toList(),
              ),

            if (_mode != SplitMode.equal && participantIds.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                _mode == SplitMode.custom
                    ? 'Enter each person\'s exact share'
                    : _mode == SplitMode.ratio
                        ? 'Enter each person\'s ratio (e.g. 1, 2, 1)'
                        : 'Enter each person\'s percentage',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              if (_mode == SplitMode.ratio || _mode == SplitMode.percentage) ...[
                _shareRow('You', _payerInputController),
                const SizedBox(height: 8),
              ],
              for (final id in participantIds) ...[
                _shareRow(people.firstWhere((p) => p.id == id).name, _controllerFor(id)),
                const SizedBox(height: 8),
              ],
            ],

            if (participantIds.isNotEmpty && total > 0) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your share: ${myShare != null ? CurrencyFormatter.format(myShare) : '—'}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13)),
                    for (final id in participantIds)
                      if (shares != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${people.firstWhere((p) => p.id == id).name}: ${CurrencyFormatter.format(shares[id] ?? 0)}',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                    if (shares == null || myShare == null || myShare < -0.01)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _modeErrorHint(),
                          style: TextStyle(color: AppColors.expense, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.expense, fontSize: 12.5)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save split', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _modeErrorHint() {
    switch (_mode) {
      case SplitMode.equal:
        return '';
      case SplitMode.custom:
        return 'The shares you entered must add up to no more than the total.';
      case SplitMode.ratio:
        return 'Enter a ratio greater than 0 for at least one person.';
      case SplitMode.percentage:
        return 'Everyone\'s percentage (including yours) must add up to 100%.';
    }
  }

  Widget _shareRow(String label, TextEditingController controller) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 13))),
        SizedBox(
          width: 100,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, IconData icon, TextEditingController controller,
      {String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: AppColors.textPrimary),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 16, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          isExpanded: true,
          value: value,
          dropdownColor: AppColors.surface,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showQuickAddPerson(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add Person', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                final added = await ref.read(financeNotifierProvider.notifier).addPerson(name);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() => _selectedPersonIds.add(added.id));
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Failed to add person: $e'), backgroundColor: AppColors.expense),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final total = double.tryParse(_amountController.text.trim());
    if (total == null || total <= 0) {
      setState(() => _error = 'Please enter a valid total bill amount');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Please select an account');
      return;
    }
    if (_selectedPersonIds.isEmpty) {
      setState(() => _error = 'Select at least one person to split with');
      return;
    }
    final payerInput = double.tryParse(_payerInputController.text.trim()) ?? 0;
    final participantIds = _selectedPersonIds.toList();
    final participantInputs = <String, double>{
      for (final id in participantIds) id: double.tryParse(_controllerFor(id).text.trim()) ?? 0,
    };
    final shares = resolveSplitShares(
      mode: _mode,
      totalAmount: total,
      participantIds: participantIds,
      participantInputs: participantInputs,
      payerInput: payerInput,
    );
    if (shares == null) {
      setState(() => _error = _modeErrorHint());
      return;
    }
    final myShare = total - shares.values.fold(0.0, (s, v) => s + v);
    if (myShare < -0.01) {
      setState(() => _error = 'The shares add up to more than the total bill');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(financeNotifierProvider.notifier).addSplitExpense(
            title: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : 'Split expense',
            totalAmount: total,
            accountId: _accountId!,
            creditCardId: _creditCardId,
            categoryId: _categoryId,
            date: _selectedDate,
            mode: _mode,
            shares: shares,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to save: $e';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Split saved!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}
