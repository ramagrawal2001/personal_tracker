import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../transactions/presentation/quick_add_modal.dart';

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final loans = financeState.loans;
    final totalLoanDebt = financeState.totalLoanDebt;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('LOANS & EMIS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, color: AppColors.primary),
            onPressed: () => _showAddLoanSheet(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Loan Liability Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.loan.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.landmark, color: AppColors.loan, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Outstanding Principal', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        const SizedBox(height: 2),
                        Text(
                          CurrencyFormatter.format(totalLoanDebt),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.loan),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Active Loans', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: loans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final loan = loans[index];
                final progress = 1.0 - (loan.outstandingAmount / loan.principalAmount);

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(loan.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.loan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text('${loan.interestRate}% p.a.', style: const TextStyle(color: AppColors.loan, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
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
                              if (v == 'edit') _showEditLoanSheet(context, ref, loan);
                              if (v == 'delete') _confirmDeleteLoan(context, ref, loan);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loan.provider,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Outstanding Principal', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              const SizedBox(height: 2),
                              Text(CurrencyFormatter.format(loan.outstandingAmount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Monthly EMI', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              const SizedBox(height: 2),
                              Text(CurrencyFormatter.format(loan.monthlyEmi), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.loan)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Repayment Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceLight,
                          color: AppColors.income,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${(progress * 100).toStringAsFixed(1)}% Paid', style: const TextStyle(fontSize: 11, color: AppColors.income, fontWeight: FontWeight.bold)),
                          Text('${loan.remainingTenureMonths} months remaining', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Due Date: ${loan.dueDay}th of every month', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.loan,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.checkCircle2, size: 14, color: Colors.white),
                            label: const Text('Pay EMI', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              QuickAddModal.show(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Add Loan ────────────────────────────────────────────────────────────────
  void _showAddLoanSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final emiCtrl = TextEditingController();
    final tenureCtrl = TextEditingController();
    int dueDay = 1;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Add Loan / EMI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Loan Name', LucideIcons.landmark)),
                const SizedBox(height: 12),
                TextField(controller: providerCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Bank / Provider', LucideIcons.building2)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: principalCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Principal (₹)', LucideIcons.indianRupee))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: rateCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Rate % p.a.', LucideIcons.percent))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: emiCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Monthly EMI (₹)', LucideIcons.calendarClock))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: tenureCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Tenure (months)', LucideIcons.clock))),
                ]),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () {
                    final p = double.tryParse(principalCtrl.text) ?? 0;
                    final r = double.tryParse(rateCtrl.text) ?? 0;
                    final e = double.tryParse(emiCtrl.text) ?? 0;
                    final t = int.tryParse(tenureCtrl.text) ?? 12;
                    if (nameCtrl.text.trim().isEmpty || p == 0) return;
                    ref.read(financeNotifierProvider.notifier).addLoan(
                      name: nameCtrl.text.trim(), provider: providerCtrl.text.trim(),
                      principalAmount: p, interestRate: r, monthlyEmi: e, dueDay: dueDay, tenureMonths: t,
                    );
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('Add Loan', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditLoanSheet(BuildContext context, WidgetRef ref, loan) {
    final nameCtrl = TextEditingController(text: loan.name);
    final outCtrl = TextEditingController(text: loan.outstandingAmount.toStringAsFixed(0));
    final emiCtrl = TextEditingController(text: loan.monthlyEmi.toStringAsFixed(0));
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit Loan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Loan Name', LucideIcons.landmark)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: outCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Outstanding (₹)', LucideIcons.indianRupee))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: emiCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Monthly EMI (₹)', LucideIcons.calendarClock))),
            ]),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                ref.read(financeNotifierProvider.notifier).updateLoan(loan.id,
                  name: nameCtrl.text.trim(),
                  outstandingAmount: double.tryParse(outCtrl.text),
                  monthlyEmi: double.tryParse(emiCtrl.text),
                );
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

  void _confirmDeleteLoan(BuildContext context, WidgetRef ref, loan) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete Loan?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: Text('Remove "${loan.name}" from your loans?', style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteLoan(loan.id); Navigator.pop(ctx); },
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
