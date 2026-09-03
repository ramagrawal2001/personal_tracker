import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/responsive.dart';

class AddCategoryModal extends ConsumerStatefulWidget {
  const AddCategoryModal({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const AddCategoryModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  ConsumerState<AddCategoryModal> createState() => _AddCategoryModalState();
}

class _AddCategoryModalState extends ConsumerState<AddCategoryModal> {
  final TextEditingController _nameController = TextEditingController();
  String _type = 'expense';
  String _selectedIcon = 'tag';
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = _type == 'expense';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
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
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add Category',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Segmented type selector
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = 'expense'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isExpense ? AppColors.expense.withValues(alpha: 0.15) : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExpense ? AppColors.expense : AppColors.border,
                          width: isExpense ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.arrowUpRight, size: 16, color: isExpense ? AppColors.expense : AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            'Expense',
                            style: TextStyle(
                              color: isExpense ? AppColors.expense : AppColors.textSecondary,
                              fontWeight: isExpense ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = 'income'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !isExpense ? AppColors.income.withValues(alpha: 0.15) : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !isExpense ? AppColors.income : AppColors.border,
                          width: !isExpense ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.arrowDownLeft, size: 16, color: !isExpense ? AppColors.income : AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            'Income',
                            style: TextStyle(
                              color: !isExpense ? AppColors.income : AppColors.textSecondary,
                              fontWeight: !isExpense ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Category Name (e.g. Subscriptions, Groceries)',
                prefixIcon: Icon(LucideIcons.tag, color: AppColors.primary, size: 18),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 18),
            Text('Icon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: categoryIconOptions.map((entry) {
                final isSelected = _selectedIcon == entry.key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = entry.key),
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

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(LucideIcons.check, size: 20),
                label: const Text('Save Category', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: _saveCategory,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveCategory() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a category name');
      return;
    }

    final existing = ref.read(financeNotifierProvider).categories;
    final duplicate = existing.any((c) => c.type == _type && c.name.toLowerCase() == name.toLowerCase());
    if (duplicate) {
      setState(() => _error = 'A category with this name already exists');
      return;
    }

    ref.read(financeNotifierProvider.notifier).addCategory(
          name: name,
          type: _type,
          icon: _selectedIcon,
        );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Category added successfully!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}
