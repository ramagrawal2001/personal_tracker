import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
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
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text(
            'DYNAMIC CATEGORIES',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.plus, color: AppColors.primary),
              onPressed: () => AddCategoryModal.show(context),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Expense Categories'),
              Tab(text: 'Income Categories'),
            ],
          ),
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final Color color = isExpense ? AppColors.expense : AppColors.income;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.tag, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  cat.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, color: AppColors.textMuted, size: 18),
                onPressed: () {
                  ref.read(financeNotifierProvider.notifier).deleteCategory(cat.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Category deleted')),
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
