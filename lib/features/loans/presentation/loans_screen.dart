import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/summary_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../transactions/presentation/quick_add_modal.dart';

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final loans = financeState.loans;
    final totalLoanDebt = financeState.totalLoanDebt;

    return AppScaffold(
      title: 'Loans & EMIs',
      actions: [
        AppScaffold.addAction(onPressed: () => _showAddLoanSheet(context, ref)),
      ],
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummaryCard(
            label: 'Total Outstanding Principal',
            value: CurrencyFormatter.format(totalLoanDebt),
            icon: LucideIcons.landmark,
            accentColor: AppColors.loan,
            valueColor: AppColors.loan,
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Active Loans'),
          if (loans.isEmpty)
            const EmptyState(
              icon: LucideIcons.landmark,
              title: 'No active loans',
              description: 'Track your home loans, personal loans, and EMIs in one place.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: loans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final loan = loans[index];
                final progress = 1.0 - (loan.outstandingAmount / loan.principalAmount);

                return AppCard(
                  radius: AppDecorations.radiusLg,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(loan.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                const SizedBox(height: 2),
                                Text(loan.provider, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.loan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${loan.interestRate}% p.a.', style: const TextStyle(color: AppColors.loan, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Edit')])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 14, color: AppColors.expense), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.expense))])),
                            ],
                            onSelected: (v) {
                              if (v == 'edit') _showEditLoanSheet(context, ref, loan);
                              if (v == 'delete') _confirmDeleteLoan(context, ref, loan);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _metric('Outstanding', CurrencyFormatter.format(loan.outstandingAmount)),
                          _metric('Monthly EMI', CurrencyFormatter.format(loan.monthlyEmi), align: CrossAxisAlignment.end, color: AppColors.loan),
                        ],
                      ),
                      const SizedBox(height: 14),
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
                          Text('${(progress * 100).toStringAsFixed(1)}% paid', style: const TextStyle(fontSize: 11, color: AppColors.income, fontWeight: FontWeight.w600)),
                          Text('${loan.remainingTenureMonths} months left', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Due: ${loan.dueDay}th monthly', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.loan,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.checkCircle2, size: 14),
                            label: const Text('Pay EMI', style: TextStyle(fontSize: 12)),
                            onPressed: () => QuickAddModal.show(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {CrossAxisAlignment align = CrossAxisAlignment.start, Color? color}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  void _showAddLoanSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final emiCtrl = TextEditingController();
    final tenureCtrl = TextEditingController();
    const dueDay = 1;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add Loan / EMI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              TextField(controller: nameCtrl, decoration: _dec('Loan Name', LucideIcons.landmark)),
              const SizedBox(height: 12),
              TextField(controller: providerCtrl, decoration: _dec('Bank / Provider', LucideIcons.building2)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: principalCtrl, keyboardType: TextInputType.number, decoration: _dec('Principal (₹)', LucideIcons.indianRupee))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: rateCtrl, keyboardType: TextInputType.number, decoration: _dec('Rate % p.a.', LucideIcons.percent))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: emiCtrl, keyboardType: TextInputType.number, decoration: _dec('Monthly EMI (₹)', LucideIcons.calendarClock))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: tenureCtrl, keyboardType: TextInputType.number, decoration: _dec('Tenure (months)', LucideIcons.clock))),
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
                child: const Text('Add Loan'),
              )),
            ]),
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
            TextField(controller: nameCtrl, decoration: _dec('Loan Name', LucideIcons.landmark)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: outCtrl, keyboardType: TextInputType.number, decoration: _dec('Outstanding (₹)', LucideIcons.indianRupee))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: emiCtrl, keyboardType: TextInputType.number, decoration: _dec('Monthly EMI (₹)', LucideIcons.calendarClock))),
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
              child: const Text('Save Changes'),
            )),
          ]),
        ),
      ),
    );
  }

  void _confirmDeleteLoan(BuildContext context, WidgetRef ref, loan) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete Loan?'),
      content: Text('Remove "${loan.name}" from your loans?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteLoan(loan.id); Navigator.pop(ctx); },
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 16, color: AppColors.textMuted),
  );
}
