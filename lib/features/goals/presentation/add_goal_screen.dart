import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';

class AddGoalScreen extends ConsumerStatefulWidget {
  const AddGoalScreen({super.key});

  @override
  ConsumerState<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends ConsumerState<AddGoalScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _savedController = TextEditingController();
  DateTime? _targetDate;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _savedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Create Savings Goal',
      showBackButton: true,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: AppDecorations.iconBadge(AppColors.primary, circle: true),
                      child: const Icon(LucideIcons.target, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Set Up Goal Bucket',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Define a target and track your automated milestones.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Goal Title (e.g. Emergency Vault, MacBook Pro)',
                    prefixIcon: Icon(LucideIcons.tag, color: AppColors.primary, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _targetController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Target Amount (${CurrencyFormatter.symbol})',
                          prefixIcon: const Icon(LucideIcons.indianRupee, color: AppColors.income, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _savedController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Already Saved (${CurrencyFormatter.symbol})',
                          prefixIcon: const Icon(LucideIcons.wallet, color: AppColors.warning, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 180)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                    );
                    if (picked != null) setState(() => _targetDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Target Date (optional)',
                      prefixIcon: Icon(LucideIcons.calendar, color: AppColors.accent, size: 18),
                    ),
                    child: Text(
                      _targetDate != null ? '${_targetDate!.day}/${_targetDate!.month}/${_targetDate!.year}' : 'No target date set',
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(LucideIcons.check, size: 20),
              label: const Text('Save Savings Goal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: _saveGoal,
            ),
          ),
        ],
      ),
    );
  }

  void _saveGoal() {
    final name = _nameController.text.trim();
    final target = double.tryParse(_targetController.text.trim()) ?? 0.0;
    final saved = double.tryParse(_savedController.text.trim()) ?? 0.0;

    if (name.isEmpty || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid goal name and target amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    ref.read(financeNotifierProvider.notifier).addGoal(
          name: name,
          targetAmount: target,
          currentSavedAmount: saved,
          targetDate: _targetDate,
        );

    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Savings Goal created!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}
