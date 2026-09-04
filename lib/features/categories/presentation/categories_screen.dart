import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
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
        bottom: TabBar(
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
                child: Icon(iconForCategoryName(cat.icon), color: color, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(LucideIcons.pencil, color: AppColors.primary, size: 16),
                onPressed: () => _showEditSheet(context, ref, cat),
              ),
              IconButton(
                icon: Icon(LucideIcons.trash2, color: AppColors.textMuted, size: 18),
                onPressed: () => _confirmDelete(context, ref, cat),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, cat) {
    final nameCtrl = TextEditingController(text: cat.name);
    String selectedIcon = cat.icon;
    String? error;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Edit Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(labelText: 'Category Name', errorText: error),
                ),
                const SizedBox(height: 16),
                Text('Icon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: categoryIconOptions.map((entry) {
                    final isSelected = selectedIcon == entry.key;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedIcon = entry.key),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceLight,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
                        ),
                        child: Icon(entry.value, size: 18, color: isSelected ? AppColors.primary : AppColors.textMuted),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setSheetState(() => error = 'Enter a category name');
                      return;
                    }
                    final allCats = ref.read(financeNotifierProvider).categories;
                    final duplicate = allCats.any((c) => c.id != cat.id && c.type == cat.type && c.name.toLowerCase() == name.toLowerCase());
                    if (duplicate) {
                      setSheetState(() => error = 'A category with this name already exists');
                      return;
                    }
                    try {
                      await ref.read(financeNotifierProvider.notifier).updateCategory(cat.id, name: name, icon: selectedIcon);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                    } catch (e) {
                      setSheetState(() => error = 'Failed to save: $e');
                    }
                  },
                  child: const Text('Save'),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete category?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "${cat.name}"? Existing transactions keep this category id but it will no longer be selectable.', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(financeNotifierProvider.notifier).deleteCategory(cat.id);
                if (!context.mounted) return;
                showUndoDeleteSnackBar(
                  context,
                  message: '"${cat.name}" deleted',
                  onUndo: () => ref.read(financeNotifierProvider.notifier).undoDelete('categories', cat.id),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.expense),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
  }
}
