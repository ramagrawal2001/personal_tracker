import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';

class AddCategoryModal extends ConsumerStatefulWidget {
  const AddCategoryModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const AddCategoryModal(),
    );
  }

  @override
  ConsumerState<AddCategoryModal> createState() => _AddCategoryModalState();
}

class _AddCategoryModalState extends ConsumerState<AddCategoryModal> {
  final TextEditingController _nameController = TextEditingController();
  String _type = 'expense';
  final String _selectedIcon = 'tag';


  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Custom Category',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Expense')),
                    selected: _type == 'expense',
                    selectedColor: AppColors.expense.withValues(alpha: 0.2),
                    onSelected: (val) {
                      if (val) setState(() => _type = 'expense');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Income')),
                    selected: _type == 'income',
                    selectedColor: AppColors.income.withValues(alpha: 0.2),
                    onSelected: (val) {
                      if (val) setState(() => _type = 'income');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name (e.g. Subscriptions, Pet Care)',
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveCategory,
                child: const Text('Save Category'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a category name')),
      );
      return;
    }

    ref.read(financeNotifierProvider.notifier).addCategory(
          name: name,
          type: _type,
          icon: _selectedIcon,
        );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Category added successfully!'), backgroundColor: AppColors.income),
    );
  }
}
