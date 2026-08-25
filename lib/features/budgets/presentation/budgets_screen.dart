import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../domain/models/models.dart';


class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final budgets = financeState.budgets;
    final categories = financeState.categories;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'MONTHLY BUDGETS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.alertTriangle, color: AppColors.warning, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You have used 90% of your Shopping budget for August.',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text('August Budgets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: budgets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final budget = budgets[index];
                final cat = categories.firstWhere(
                  (c) => c.id == budget.categoryId,
                  orElse: () => CategoryModel(id: '', name: 'General', type: 'expense', icon: 'tag'),
                );

                final pct = budget.percentage;
                final isWarning = pct >= 0.85;

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
                          Expanded(child: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16))),
                          Text('${CurrencyFormatter.format(budget.spentAmount)} / ${CurrencyFormatter.format(budget.monthlyLimit)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: isWarning ? AppColors.expense : AppColors.textPrimary, fontSize: 13)),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Edit Limit', style: TextStyle(color: AppColors.textPrimary))])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 14, color: AppColors.expense), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.expense))])),
                            ],
                            onSelected: (v) {
                              if (v == 'edit') _showEditBudgetSheet(context, ref, budget);
                              if (v == 'delete') _confirmDeleteBudget(context, ref, budget);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 10,
                          backgroundColor: AppColors.surfaceLight,
                          color: isWarning ? AppColors.expense : AppColors.income,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(pct * 100).toInt()}% Used',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isWarning ? AppColors.expense : AppColors.income),
                          ),
                          Text(
                            'Remaining: ${CurrencyFormatter.format(budget.remaining > 0 ? budget.remaining : 0.0)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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

  void _showEditBudgetSheet(BuildContext context, WidgetRef ref, budget) {
    final limitCtrl = TextEditingController(text: budget.monthlyLimit.toStringAsFixed(0));
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit Budget Limit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            TextField(
              controller: limitCtrl, keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Monthly Limit (₹)', prefixIcon: const Icon(LucideIcons.indianRupee, size: 16, color: AppColors.textMuted),
                filled: true, fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                final limit = double.tryParse(limitCtrl.text);
                if (limit != null) ref.read(financeNotifierProvider.notifier).updateBudget(budget.id, limitAmount: limit);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ),
      ),
    );
  }

  void _confirmDeleteBudget(BuildContext context, WidgetRef ref, budget) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete Budget?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: const Text('Remove this budget?', style: TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () { ref.read(financeNotifierProvider.notifier).deleteBudget(budget.id); Navigator.pop(ctx); },
          child: const Text('Delete'),
        ),
      ],
    ));
  }
}
