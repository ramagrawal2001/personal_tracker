import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../domain/models/models.dart';
import '../../../core/utils/responsive.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final budgets = financeState.budgetsWithCalculatedSpend;
    final categories = financeState.categories;
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    final warningBudget = budgets.where((b) => b.percentage >= 0.85).toList();
    warningBudget.sort((a, b) => b.percentage.compareTo(a.percentage));

    return AppScaffold(
      title: 'Monthly Budgets',
      scrollable: true,
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.plus, color: AppColors.primary),
          onPressed: () => _showAddBudgetSheet(context, ref, budgets, categories),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warningBudget.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppDecorations.alertBanner(AppColors.warning),
              child: Row(
                children: [
                  const Icon(LucideIcons.alertTriangle, color: AppColors.warning, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _warningMessage(warningBudget.first, categories),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          SectionHeader(title: '$monthLabel Budgets'),
          if (budgets.isEmpty)
            const EmptyState(
              icon: LucideIcons.pieChart,
              title: 'No budgets set',
              description: 'Create category budgets to track your monthly spending limits.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: budgets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final budget = budgets[index];
                final cat = categories.firstWhere(
                  (c) => c.id == budget.categoryId,
                  orElse: () => CategoryModel(id: '', name: 'General', type: 'expense', icon: 'tag'),
                );
                final pct = budget.percentage;
                final isWarning = pct >= 0.85;

                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cat.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15),
                            ),
                          ),
                          Text(
                            '${CurrencyFormatter.format(budget.spentAmount)} / ${CurrencyFormatter.format(budget.monthlyLimit)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isWarning ? AppColors.expense : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.pencil, size: 14, color: AppColors.primary), SizedBox(width: 8), Text('Edit Limit')])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 14, color: AppColors.expense), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.expense))])),
                            ],
                            onSelected: (v) {
                              if (v == 'edit') _showEditBudgetSheet(context, ref, budget);
                              if (v == 'delete') _confirmDeleteBudget(context, ref, budget);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceLight,
                          color: isWarning ? AppColors.expense : AppColors.income,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(pct * 100).toInt()}% used',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isWarning ? AppColors.expense : AppColors.income),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _warningMessage(budget, List categories) {
    final cat = categories.firstWhere(
      (c) => c.id == budget.categoryId,
      orElse: () => CategoryModel(id: '', name: 'a category', type: 'expense', icon: 'tag'),
    );
    return "You've used ${(budget.percentage * 100).toInt()}% of your ${cat.name} budget this month.";
  }

  void _showEditBudgetSheet(BuildContext context, WidgetRef ref, budget) {
    final limitCtrl = TextEditingController(text: budget.monthlyLimit.toStringAsFixed(0));
    String? error;
    AdaptiveModal.show(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Edit Budget Limit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              TextField(
                controller: limitCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monthly Limit (${CurrencyFormatter.symbol})',
                  prefixIcon: const Icon(LucideIcons.indianRupee, size: 16),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final limit = double.tryParse(limitCtrl.text);
                    if (limit == null || limit <= 0) {
                      setSheetState(() => error = 'Enter a limit greater than 0');
                      return;
                    }
                    ref.read(financeNotifierProvider.notifier).updateBudget(budget.id, limitAmount: limit);
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showAddBudgetSheet(BuildContext context, WidgetRef ref, List<BudgetModel> existingBudgets, List<CategoryModel> categories) {
    final expenseCategories = categories.where((c) => c.type == 'expense').toList();
    final now = DateTime.now();
    final monthYear = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final budgetedCategoryIds = existingBudgets.where((b) => b.monthYear == monthYear).map((b) => b.categoryId).toSet();
    final availableCategories = expenseCategories.where((c) => !budgetedCategoryIds.contains(c.id)).toList();

    if (availableCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every expense category already has a budget this month.'), backgroundColor: AppColors.warning),
      );
      return;
    }

    String selectedCategoryId = availableCategories.first.id;
    final limitCtrl = TextEditingController();
    String? error;

    AdaptiveModal.show(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('New Monthly Budget', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                dropdownColor: AppColors.surface,
                items: availableCategories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setSheetState(() => selectedCategoryId = v ?? selectedCategoryId),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: limitCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monthly Limit (${CurrencyFormatter.symbol})',
                  prefixIcon: const Icon(LucideIcons.indianRupee, size: 16),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final limit = double.tryParse(limitCtrl.text);
                    if (limit == null || limit <= 0) {
                      setSheetState(() => error = 'Enter a limit greater than 0');
                      return;
                    }
                    ref.read(financeNotifierProvider.notifier).addBudget(categoryId: selectedCategoryId, monthlyLimit: limit, monthYear: monthYear);
                    Navigator.pop(context);
                  },
                  child: const Text('Create Budget'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteBudget(BuildContext context, WidgetRef ref, budget) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Budget?'),
        content: const Text('Remove this budget?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () {
              ref.read(financeNotifierProvider.notifier).deleteBudget(budget.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
