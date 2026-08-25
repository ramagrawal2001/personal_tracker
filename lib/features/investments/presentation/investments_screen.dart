import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'INVESTMENTS & SIPS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, color: AppColors.primary),
            onPressed: () => AddInvestmentModal.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Portfolio Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.surface,
                    const Color(0xFF1E1B4B),
                    const Color(0xFF0F172A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('INVESTMENT PORTFOLIO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted)),
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
                  const SizedBox(height: 10),
                  Text(
                    CurrencyFormatter.format(totalCurrent),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Invested', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(totalInvested), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('Net Gain', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text('${totalGain >= 0 ? "+" : ""}${CurrencyFormatter.format(totalGain)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: totalGain >= 0 ? AppColors.income : AppColors.expense)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Monthly SIP', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text(CurrencyFormatter.format(monthlySipTotal), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.transfer)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Manual Portfolio Holdings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: investments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final inv = investments[index];
                final isGain = inv.netReturns >= 0;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(inv.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                            child: Text(inv.type.displayName, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Update Value', style: TextStyle(color: AppColors.textPrimary))])),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Current Valuation', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              const SizedBox(height: 2),
                              Text(CurrencyFormatter.format(inv.currentValue), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Invested Amount', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              const SizedBox(height: 2),
                              Text(CurrencyFormatter.format(inv.investedAmount), style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Returns: ${isGain ? "+" : ""}${CurrencyFormatter.format(inv.netReturns)} (${inv.returnsPercentage.toStringAsFixed(1)}%)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isGain ? AppColors.income : AppColors.expense),
                          ),
                          if (inv.monthlySipAmount > 0)
                            Text(
                              'SIP: ${CurrencyFormatter.format(inv.monthlySipAmount)} / mo (${inv.sipDay}th)',
                              style: const TextStyle(fontSize: 12, color: AppColors.transfer, fontWeight: FontWeight.w600),
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

  void _showEditInvestmentSheet(BuildContext context, WidgetRef ref, inv) {
    final nameCtrl = TextEditingController(text: inv.name);
    final currentCtrl = TextEditingController(text: inv.currentValue.toStringAsFixed(0));
    final sipCtrl = TextEditingController(text: inv.monthlySipAmount > 0 ? inv.monthlySipAmount.toStringAsFixed(0) : '');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Update Investment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Investment Name', LucideIcons.trendingUp)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: currentCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Current Value (₹)', LucideIcons.indianRupee))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: sipCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _dec('Monthly SIP (₹)', LucideIcons.repeat))),
            ]),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                ref.read(financeNotifierProvider.notifier).updateInvestment(inv.id,
                  name: nameCtrl.text.trim(),
                  currentValue: double.tryParse(currentCtrl.text),
                  monthlySipAmount: double.tryParse(sipCtrl.text) ?? 0,
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

  void _confirmDeleteInvestment(BuildContext context, WidgetRef ref, inv) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Remove Investment?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: Text('Remove "${inv.name}" from your portfolio?', style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteInvestment(inv.id); Navigator.pop(ctx); },
          child: const Text('Remove'),
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
