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
import '../../../core/widgets/empty_state.dart';
import 'add_investment_modal.dart';

class InvestmentsScreen extends ConsumerWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final investments = financeState.investments;
    final totalInvested = financeState.totalInvestedAmount;
    final totalCurrent = financeState.totalInvestmentCurrentValue;
    final totalGain = totalCurrent - totalInvested;
    final overallReturnPct = totalInvested > 0 ? (totalGain / totalInvested) * 100 : 0.0;
    final monthlySipTotal = financeState.totalMonthlySipAmount;

    return AppScaffold(
      title: 'Investments',
      actions: [
        AppScaffold.addAction(onPressed: () => AddInvestmentModal.show(context)),
      ],
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppDecorations.surfaceGradient(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('PORTFOLIO VALUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textMuted)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (totalGain >= 0 ? AppColors.income : AppColors.expense).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(totalGain >= 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown, color: totalGain >= 0 ? AppColors.income : AppColors.expense, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${totalGain >= 0 ? "+" : ""}${overallReturnPct.toStringAsFixed(1)}%',
                            style: TextStyle(color: totalGain >= 0 ? AppColors.income : AppColors.expense, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(CurrencyFormatter.format(totalCurrent), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _stat('Invested', CurrencyFormatter.format(totalInvested)),
                    _stat('Net Gain', '${totalGain >= 0 ? "+" : ""}${CurrencyFormatter.format(totalGain)}', color: totalGain >= 0 ? AppColors.income : AppColors.expense),
                    _stat('Monthly SIP', CurrencyFormatter.format(monthlySipTotal), color: AppColors.transfer, align: CrossAxisAlignment.end),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Holdings'),
          if (investments.isEmpty)
            EmptyState(
              icon: LucideIcons.trendingUp,
              title: 'No investments yet',
              description: 'Track your stocks, mutual funds, and SIPs here.',
              actionLabel: 'Add Investment',
              onAction: () => AddInvestmentModal.show(context),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: investments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final inv = investments[index];
                final isGain = inv.netReturns >= 0;

                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(inv.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: AppDecorations.iconBadge(AppColors.primary),
                            child: Text(inv.type.displayName, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Update Value')])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 14, color: AppColors.expense), SizedBox(width: 8), Text('Remove', style: TextStyle(color: AppColors.expense))])),
                            ],
                            onSelected: (v) {
                              if (v == 'edit') _showEditInvestmentSheet(context, ref, inv);
                              if (v == 'delete') _confirmDeleteInvestment(context, ref, inv);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _stat('Current Value', CurrencyFormatter.format(inv.currentValue)),
                          _stat('Invested', CurrencyFormatter.format(inv.investedAmount), align: CrossAxisAlignment.end),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Returns: ${isGain ? "+" : ""}${CurrencyFormatter.format(inv.netReturns)} (${inv.returnsPercentage.toStringAsFixed(1)}%)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isGain ? AppColors.income : AppColors.expense),
                          ),
                          if (inv.monthlySipAmount > 0)
                            Text(
                              'SIP: ${CurrencyFormatter.format(inv.monthlySipAmount)}/mo',
                              style: const TextStyle(fontSize: 12, color: AppColors.transfer, fontWeight: FontWeight.w600),
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

  Widget _stat(String label, String value, {Color? color, CrossAxisAlignment align = CrossAxisAlignment.start}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  void _showEditInvestmentSheet(BuildContext context, WidgetRef ref, inv) {
    final nameCtrl = TextEditingController(text: inv.name);
    final investedCtrl = TextEditingController(text: inv.investedAmount.toStringAsFixed(0));
    final currentCtrl = TextEditingController(text: inv.currentValue.toStringAsFixed(0));
    final sipCtrl = TextEditingController(text: inv.monthlySipAmount > 0 ? inv.monthlySipAmount.toStringAsFixed(0) : '');
    String? error;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Update Investment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Investment Name', prefixIcon: Icon(LucideIcons.trendingUp, size: 16))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: investedCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Invested (₹)', prefixIcon: Icon(LucideIcons.indianRupee, size: 16)))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: currentCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current Value (₹)', prefixIcon: Icon(LucideIcons.indianRupee, size: 16)))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: sipCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly SIP (₹)', prefixIcon: Icon(LucideIcons.repeat, size: 16))),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.expense, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () {
                    final invested = double.tryParse(investedCtrl.text);
                    final current = double.tryParse(currentCtrl.text);
                    final sip = double.tryParse(sipCtrl.text) ?? 0;
                    if (nameCtrl.text.trim().isEmpty) {
                      setSheetState(() => error = 'Enter an investment name');
                      return;
                    }
                    if (invested == null || invested < 0) {
                      setSheetState(() => error = 'Enter a valid invested amount');
                      return;
                    }
                    if (current == null || current < 0) {
                      setSheetState(() => error = 'Enter a valid current value');
                      return;
                    }
                    if (sip < 0) {
                      setSheetState(() => error = 'Monthly SIP cannot be negative');
                      return;
                    }
                    ref.read(financeNotifierProvider.notifier).updateInvestment(inv.id,
                      name: nameCtrl.text.trim(),
                      investedAmount: invested,
                      currentValue: current,
                      monthlySipAmount: sip,
                    );
                    Navigator.pop(context);
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

  void _confirmDeleteInvestment(BuildContext context, WidgetRef ref, inv) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove Investment?'),
      content: Text('Remove "${inv.name}" from your portfolio?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteInvestment(inv.id); Navigator.pop(ctx); },
          child: const Text('Remove'),
        ),
      ],
    ));
  }
}
