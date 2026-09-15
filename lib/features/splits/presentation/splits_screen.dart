import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/summary_card.dart';
import '../../../domain/models/models.dart';
import 'split_expense_modal.dart';

/// Split expenses (IOU tracking) — who owes you what from bills you paid in
/// full. The real expense (full amount) already hit your account balance
/// when it was logged; this screen is purely the tracking/settlement layer
/// on top, per FinanceNotifier.addSplitExpense / totalReceivables.
class SplitsScreen extends ConsumerWidget {
  const SplitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final splits = [...financeState.splitExpenses]..sort((a, b) => b.date.compareTo(a.date));
    final receivablesByPerson = financeState.receivablesByPerson();
    final peopleById = {for (final p in financeState.people) p.id: p};

    return AppScaffold(
      title: 'Splits',
      actions: [
        AppScaffold.addAction(onPressed: () => SplitExpenseModal.show(context)),
      ],
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummaryCard(
            label: "You're Owed",
            value: CurrencyFormatter.format(financeState.totalReceivables),
            icon: LucideIcons.coins,
            accentColor: AppColors.income,
            valueColor: AppColors.textPrimary,
          ),
          if (receivablesByPerson.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'By Person'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: receivablesByPerson.entries.map((e) {
                final name = peopleById[e.key]?.name ?? 'Unknown';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$name owes ${CurrencyFormatter.format(e.value)}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          const SectionHeader(title: 'All Splits'),
          if (splits.isEmpty)
            EmptyState(
              icon: LucideIcons.users,
              title: 'No splits yet',
              description: 'Split a bill from Add Transaction, or tap + here, to track what others owe you.',
              actionLabel: 'Split an Expense',
              onAction: () => SplitExpenseModal.show(context),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: splits.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _SplitCard(split: splits[index], peopleById: peopleById),
            ),
        ],
      ),
    );
  }
}

class _SplitCard extends ConsumerWidget {
  final SplitExpenseModel split;
  final Map<String, PersonModel> peopleById;
  const _SplitCard({required this.split, required this.peopleById});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref
        .watch(financeNotifierProvider)
        .splitParticipants
        .where((p) => !p.isDeleted && p.splitExpenseId == split.id)
        .toList();
    final unsettledTotal = participants.where((p) => !p.isSettled).fold(0.0, (s, p) => s + p.shareAmount);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.iconBadge(AppColors.primary, circle: true),
                child: Icon(LucideIcons.receipt, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(split.title, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15)),
                    Text(
                      '${DateFormatter.formatShort(split.date)} • ${CurrencyFormatter.format(split.totalAmount)} total',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (unsettledTotal > 0)
                Text(CurrencyFormatter.format(unsettledTotal), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.income, fontSize: 14))
              else
                Icon(LucideIcons.checkCircle2, color: AppColors.income, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in participants) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${peopleById[p.personId]?.name ?? 'Unknown'} • ${CurrencyFormatter.format(p.shareAmount)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: p.isSettled ? AppColors.textMuted : AppColors.textPrimary,
                        decoration: p.isSettled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (p.isSettled)
                    Text('Settled', style: TextStyle(fontSize: 11, color: AppColors.income, fontWeight: FontWeight.w600))
                  else
                    TextButton(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                      onPressed: () => _showSettleSheet(context, ref, p),
                      child: const Text('Settle', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSettleSheet(BuildContext context, WidgetRef ref, SplitParticipantModel participant) {
    final accounts = ref.read(financeNotifierProvider).accountsWithCalculatedBalances.where((a) => !a.isDeleted).toList();
    String? selectedAccountId = accounts.isNotEmpty ? accounts.first.id : null;
    bool recordAsTransaction = false;
    String? error;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mark as settled', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('${CurrencyFormatter.format(participant.shareAmount)} — ${peopleById[participant.personId]?.name ?? 'Unknown'}',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('They paid via bank/UPI', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                subtitle: Text('Records a credit to your account. Leave off if they handed you cash.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                value: recordAsTransaction,
                onChanged: (v) => setSheetState(() => recordAsTransaction = v),
              ),
              if (recordAsTransaction) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedAccountId,
                  dropdownColor: AppColors.surface,
                  decoration: const InputDecoration(labelText: 'Credit to account'),
                  items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                  onChanged: (v) => setSheetState(() => selectedAccountId = v),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: AppColors.expense, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary),
                  onPressed: () async {
                    if (recordAsTransaction && selectedAccountId == null) {
                      setSheetState(() => error = 'Select an account');
                      return;
                    }
                    try {
                      await ref.read(financeNotifierProvider.notifier).settleSplitParticipant(
                            participant.id,
                            recordAsTransaction: recordAsTransaction,
                            accountId: recordAsTransaction ? selectedAccountId : null,
                          );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                    } catch (e) {
                      setSheetState(() => error = 'Failed: $e');
                    }
                  },
                  child: const Text('Confirm'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
