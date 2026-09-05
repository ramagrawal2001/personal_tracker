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

/// Logs a salary credit: net amount to a bank account, attached to a
/// company, with an optional PF contribution that bumps a PF/EPF investment
/// without double-debiting the bank account (see FinanceNotifier.logSalary).
class LogSalaryModal extends ConsumerStatefulWidget {
  const LogSalaryModal({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const LogSalaryModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  ConsumerState<LogSalaryModal> createState() => _LogSalaryModalState();
}

class _LogSalaryModalState extends ConsumerState<LogSalaryModal> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _pfController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  String? _companyId;
  String? _accountId;
  String? _pfInvestmentId;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _pfController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final companies = financeState.companies.where((c) => !c.isDeleted).toList();
    final accounts = financeState.accountsWithCalculatedBalances.where((a) => !a.isDeleted).toList();
    final pfInvestments = financeState.investments.where((i) => !i.isDeleted && i.type == InvestmentType.epf).toList();

    if (!companies.any((c) => c.id == _companyId)) {
      final current = companies.where((c) => c.isCurrentEmployer).toList();
      _companyId = current.isNotEmpty ? current.first.id : (companies.isNotEmpty ? companies.first.id : null);
      _applyCompanyDefaults(companies);
    }
    if (!accounts.any((a) => a.id == _accountId)) {
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
    if (!pfInvestments.any((i) => i.id == _pfInvestmentId)) {
      _pfInvestmentId = pfInvestments.isNotEmpty ? pfInvestments.first.id : null;
    }

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Log Salary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                IconButton(
                  icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text('Company', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            if (companies.isEmpty)
              _NoCompanyHint(onAddCompany: () => _showQuickAddCompany(context))
            else
              _dropdown<String>(
                value: _companyId,
                items: companies
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _companyId = v;
                  _applyCompanyDefaults(companies);
                }),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(LucideIcons.plus, size: 14, color: AppColors.primary),
                label: Text('Add company', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                onPressed: () => _showQuickAddCompany(context),
              ),
            ),
            const SizedBox(height: 10),

            Text('Credited To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            _dropdown<String>(
              value: _accountId,
              items: accounts
                  .map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (${CurrencyFormatter.format(a.calculatedBalance)})', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 14),

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
            const SizedBox(height: 14),

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
                autofocus: true,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Net Amount Credited',
                  labelStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  prefixText: '${CurrencyFormatter.symbol} ',
                  prefixStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.income),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 14),

            Text('PF Contribution (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _pfController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'e.g. 3600',
                prefixText: '${CurrencyFormatter.symbol} ',
              ),
            ),
            if (_pfController.text.trim().isNotEmpty && double.tryParse(_pfController.text.trim()) != null && double.parse(_pfController.text.trim()) > 0) ...[
              const SizedBox(height: 10),
              if (pfInvestments.isEmpty)
                Text(
                  'Add a PF investment first (Invest → EPF / PF) to track this contribution.',
                  style: TextStyle(fontSize: 12, color: AppColors.expense),
                )
              else ...[
                Text('Add To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _dropdown<String>(
                  value: _pfInvestmentId,
                  items: pfInvestments
                      .map((i) => DropdownMenuItem(value: i.id, child: Text('${i.name} (${CurrencyFormatter.format(i.currentValue)})', overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _pfInvestmentId = v),
                ),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Icon(LucideIcons.creditCard, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Deducted before it reached your bank — only the net amount above hits your account.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 14),

            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (Optional)'),
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
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Salary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyCompanyDefaults(List<CompanyModel> companies) {
    if (_companyId == null) return;
    CompanyModel? company;
    for (final c in companies) {
      if (c.id == _companyId) {
        company = c;
        break;
      }
    }
    if (company == null) return;
    if (company.defaultBankAccountId != null) _accountId = company.defaultBankAccountId;
    if (company.defaultPfAmount != null && _pfController.text.trim().isEmpty) {
      _pfController.text = company.defaultPfAmount!.toStringAsFixed(0);
    }
  }

  Widget _dropdown<T>({required T? value, required List<DropdownMenuItem<T>> items, required void Function(T?) onChanged}) {
    return DropdownButtonFormField<T>(
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
    );
  }

  void _showQuickAddCompany(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add Company', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Company Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                await ref.read(financeNotifierProvider.notifier).addCompany(name: name, isCurrentEmployer: true);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                final added = ref.read(financeNotifierProvider).companies.firstWhere((c) => c.name == name);
                setState(() => _companyId = added.id);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Failed to add company: $e'), backgroundColor: AppColors.expense),
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
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid net amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or add a company'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final pf = double.tryParse(_pfController.text.trim());
    if (pf != null && pf > 0 && _pfInvestmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a PF investment to track this contribution, or clear the PF amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(financeNotifierProvider.notifier).logSalary(
            companyId: _companyId!,
            bankAccountId: _accountId!,
            netAmount: amount,
            pfContribution: (pf != null && pf > 0) ? pf : null,
            pfInvestmentId: (pf != null && pf > 0) ? _pfInvestmentId : null,
            date: _selectedDate,
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save salary: $e'), backgroundColor: AppColors.expense, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Salary logged!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}

class _NoCompanyHint extends StatelessWidget {
  final VoidCallback onAddCompany;
  const _NoCompanyHint({required this.onAddCompany});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.building2, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text('No companies yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          TextButton(onPressed: onAddCompany, child: const Text('Add')),
        ],
      ),
    );
  }
}
