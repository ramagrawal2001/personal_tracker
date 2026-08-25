import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/summary_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../domain/models/models.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(financeNotifierProvider).goals;
    final totalTarget = goals.fold(0.0, (sum, g) => sum + g.targetAmount);
    final totalSaved = goals.fold(0.0, (sum, g) => sum + g.currentSavedAmount);
    final overallPercentage = totalTarget > 0 ? (totalSaved / totalTarget) * 100 : 0.0;

    return AppScaffold(
      title: 'Savings Goals & Buckets',
      actions: [
        AppScaffold.addAction(onPressed: () => context.push('/goals/add')),
      ],
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall Savings Summary Card
          SummaryCard(
            label: 'Total Saved towards Goals',
            value: CurrencyFormatter.format(totalSaved),
            icon: LucideIcons.target,
            accentColor: AppColors.income,
            gradient: true,
            badge: '${overallPercentage.toStringAsFixed(1)}% Achieved',
            badgeColor: AppColors.income,
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Target: ${CurrencyFormatter.format(totalTarget)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    Text(
                      '${CurrencyFormatter.format(totalTarget - totalSaved > 0 ? totalTarget - totalSaved : 0)} left',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: totalTarget > 0 ? (totalSaved / totalTarget).clamp(0.0, 1.0) : 0.0,
                    minHeight: 8,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.income),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Your Goal Buckets'),

          if (goals.isEmpty)
            EmptyState(
              icon: LucideIcons.target,
              title: 'No savings goals set',
              description: 'Create savings buckets for vacations, gadgets, or emergency funds to track your milestones.',
              actionLabel: 'Create Goal Bucket',
              onAction: () => context.push('/goals/add'),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: goals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final goal = goals[index];
                return _buildGoalCard(context, ref, goal);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(BuildContext context, WidgetRef ref, GoalModel goal) {
    final pct = (goal.progressPercentage * 100).toStringAsFixed(1);
    final isCompleted = goal.progressPercentage >= 1.0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: AppDecorations.iconBadge(
                      isCompleted ? AppColors.income : AppColors.primary,
                      circle: true,
                    ),
                    child: Icon(
                      isCompleted ? LucideIcons.checkCircle : LucideIcons.target,
                      color: isCompleted ? AppColors.income : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCompleted ? 'Goal Completed 🎉' : '$pct% completed',
                        style: TextStyle(
                          color: isCompleted ? AppColors.income : AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.pencil, color: AppColors.primary, size: 16),
                    onPressed: () => _showEditGoalSheet(context, ref, goal),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.trash2, color: AppColors.textMuted, size: 18),
                    onPressed: () => _confirmDeleteGoal(context, ref, goal),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Saved: ${CurrencyFormatter.format(goal.currentSavedAmount)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.income, fontSize: 14),
              ),
              Text(
                'Target: ${CurrencyFormatter.format(goal.targetAmount)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal.progressPercentage,
              minHeight: 6,
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? AppColors.income : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(LucideIcons.plusCircle, size: 16, color: AppColors.primary),
                label: const Text(
                  'Add Funds',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
                onPressed: () => _showAddFundsDialog(context, ref, goal),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddFundsDialog(BuildContext context, WidgetRef ref, GoalModel goal) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Deposit to ${goal.name}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Deposit Amount (₹)',
            prefixIcon: Icon(LucideIcons.indianRupee, color: AppColors.income, size: 18),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final amt = double.tryParse(controller.text.trim()) ?? 0.0;
              if (amt > 0) {
                ref.read(financeNotifierProvider.notifier).addFundsToGoal(goal.id, amt);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Funds added to goal!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
                );
              }
            },
            child: const Text('Deposit'),
          ),
        ],
      ),
    );
  }

  void _showEditGoalSheet(BuildContext context, WidgetRef ref, GoalModel goal) {
    final nameCtrl = TextEditingController(text: goal.name);
    final targetCtrl = TextEditingController(text: goal.targetAmount.toStringAsFixed(0));
    DateTime? targetDate = goal.targetDate;
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
                const Text('Edit Goal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Goal Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(labelText: 'Target Amount (₹)', errorText: error),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: targetDate ?? DateTime.now().add(const Duration(days: 180)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                    );
                    if (picked != null) setSheetState(() => targetDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Target Date'),
                    child: Text(
                      targetDate != null ? '${targetDate!.day}/${targetDate!.month}/${targetDate!.year}' : 'No target date',
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final target = double.tryParse(targetCtrl.text);
                    if (name.isEmpty) {
                      setSheetState(() => error = 'Enter a goal name');
                      return;
                    }
                    if (target == null || target <= 0) {
                      setSheetState(() => error = 'Enter a target amount greater than 0');
                      return;
                    }
                    ref.read(financeNotifierProvider.notifier).updateGoal(
                      goal.id,
                      name: name,
                      targetAmount: target,
                      targetDate: targetDate,
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

  void _confirmDeleteGoal(BuildContext context, WidgetRef ref, GoalModel goal) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete goal?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "${goal.name}"? This cannot be undone.', style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(financeNotifierProvider.notifier).deleteGoal(goal.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Goal deleted'), behavior: SnackBarBehavior.floating),
              );
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
  }
}
