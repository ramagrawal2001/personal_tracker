import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import 'add_category_modal.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(financeNotifierProvider).categories;
    final expenseCategories = categories.where((c) => c.type == 'expense').toList();
    final incomeCategories = categories.where((c) => c.type == 'income').toList();

    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        title: 'Dynamic Categories',
        showBackButton: true,
        actions: [
          AppScaffold.addAction(onPressed: () => AddCategoryModal.show(context)),
        ],
        bottom: const TabBar(
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: TextStyle(fontSize: 13),
          tabs: [
            Tab(text: 'Expense Categories'),
            Tab(text: 'Income Categories'),
          ],
        ),
        body: TabBarView(
          children: [
            _buildCategoryList(context, ref, expenseCategories, isExpense: true),
            _buildCategoryList(context, ref, incomeCategories, isExpense: false),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context, WidgetRef ref, List categories, {required bool isExpense}) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: EmptyState(
            icon: LucideIcons.tag,
            title: isExpense ? 'No expense categories' : 'No income categories',
            description: 'Create custom categories to accurately organize and track transactions.',
            actionLabel: 'Add Category',
            onAction: () => AddCategoryModal.show(context),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final Color color = isExpense ? AppColors.expense : AppColors.income;

        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.iconBadge(color),
                child: Icon(LucideIcons.tag, color: color, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  cat.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, color: AppColors.textMuted, size: 18),
                onPressed: () {
                  ref.read(financeNotifierProvider.notifier).deleteCategory(cat.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Category deleted'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
