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
/// full, and what you owe others. The real expense/repayment transaction
/// (full amount) hits your account balance when it's logged; this screen is
/// purely the tracking/settlement layer on top, per
/// FinanceNotifier.addSplitExpense/addPayable/personBalance.
class SplitsScreen extends ConsumerWidget {
  const SplitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeState = ref.watch(financeNotifierProvider);
    final splits = [...financeState.splitExpenses]..sort((a, b) => b.date.compareTo(a.date));
    final balances = financeState.allPersonBalances(); // personId -> net (positive = they owe you)
    final peopleById = {for (final p in financeState.people) p.id: p};

    return AppScaffold(
      title: 'Splits',
      actions: [
        IconButton(
          tooltip: 'Manage people',
          icon: Icon(LucideIcons.users, color: AppColors.primary),
          onPressed: () => _showManagePeopleSheet(context, ref),
        ),
        PopupMenuButton<String>(
          icon: Icon(LucideIcons.plus, color: AppColors.primary),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'split', child: Text('Split a bill')),
            const PopupMenuItem(value: 'payable', child: Text('I owe someone')),
          ],
          onSelected: (v) {
            if (v == 'split') SplitExpenseModal.show(context);
            if (v == 'payable') _showAddPayableSheet(context, ref);
          },
        ),
      ],
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: "You're Owed",
                  value: CurrencyFormatter.format(financeState.totalReceivables),
                  icon: LucideIcons.coins,
                  accentColor: AppColors.income,
                  valueColor: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: 'You Owe',
                  value: CurrencyFormatter.format(financeState.totalPayables),
                  icon: LucideIcons.wallet,
                  accentColor: AppColors.expense,
                  valueColor: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (balances.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'By Person'),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: balances.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final personId = balances.keys.elementAt(i);
                final net = balances[personId]!;
                final name = peopleById[personId]?.name ?? 'Unknown';
                final theyOweYou = net > 0;
                return AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 14)),
                            Text(theyOweYou ? 'owes you' : 'you owe',
                                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(net.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: theyOweYou ? AppColors.income : AppColors.expense,
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => theyOweYou
                            ? _showSettleReceivableSheet(context, ref, personId, name, net)
                            : _showSettlePayableSheet(context, ref, personId, name, -net),
                        child: const Text('Settle'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          const SectionHeader(title: 'All Splits'),
          if (splits.isEmpty)
            EmptyState(
              icon: LucideIcons.users,
              title: 'No splits yet',
              description: 'Split a bill from Add Transaction, or use the + menu here, to track what others owe you.',
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

  void _showManagePeopleSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final people = sheetRef.watch(financeNotifierProvider).people.where((p) => !p.isDeleted).toList();
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('People', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                if (people.isEmpty)
                  Text('No people yet — add one from Split an Expense.', style: TextStyle(color: AppColors.textMuted))
                else
                  ...people.map((p) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name, style: TextStyle(color: AppColors.textPrimary)),
                        subtitle: p.phone != null || p.upiId != null
                            ? Text([if (p.phone != null) p.phone!, if (p.upiId != null) p.upiId!].join(' • '),
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12))
                            : null,
                        trailing: Icon(LucideIcons.pencil, size: 16, color: AppColors.textMuted),
                        onTap: () => _showEditPersonSheet(context, ref, p),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditPersonSheet(BuildContext context, WidgetRef ref, PersonModel person) {
    final nameCtrl = TextEditingController(text: person.name);
    final phoneCtrl = TextEditingController(text: person.phone ?? '');
    final upiCtrl = TextEditingController(text: person.upiId ?? '');
    final notesCtrl = TextEditingController(text: person.notes ?? '');
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Edit ${person.name}', style: TextStyle(color: AppColors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                TextField(controller: upiCtrl, decoration: const InputDecoration(labelText: 'UPI ID')),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: AppColors.expense, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setSheetState(() => error = 'Enter a name');
                  return;
                }
                try {
                  await ref.read(financeNotifierProvider.notifier).updatePerson(
                        person.id,
                        name: name,
                        phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                        upiId: upiCtrl.text.trim().isNotEmpty ? upiCtrl.text.trim() : null,
                        notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                      );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                } catch (e) {
                  setSheetState(() => error = 'Failed: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPayableSheet(BuildContext context, WidgetRef ref) {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? personId;
    DateTime date = DateTime.now();
    String? error;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final people = ref.read(financeNotifierProvider).people.where((p) => !p.isDeleted).toList();
          if (!people.any((p) => p.id == personId)) personId = people.isNotEmpty ? people.first.id : null;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('I owe someone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Not linked to any of your transactions — you record the real payment when you settle it.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 16),
                if (people.isEmpty)
                  Text('Add a person first, from Split an Expense.', style: TextStyle(color: AppColors.textMuted))
                else
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: personId,
                    dropdownColor: AppColors.surface,
                    decoration: const InputDecoration(labelText: 'Who'),
                    items: people.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (v) => setSheetState(() => personId = v),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'What for'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx, initialDate: date, firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setSheetState(() => date = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(LucideIcons.calendar, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text(DateFormatter.formatShort(date), style: TextStyle(color: AppColors.textPrimary)),
                    ]),
                  ),
                ),
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
                    onPressed: people.isEmpty
                        ? null
                        : () async {
                            final amount = double.tryParse(amountCtrl.text.trim());
                            if (amount == null || amount <= 0) {
                              setSheetState(() => error = 'Enter a valid amount');
                              return;
                            }
                            if (personId == null) {
                              setSheetState(() => error = 'Select a person');
                              return;
                            }
                            try {
                              await ref.read(financeNotifierProvider.notifier).addPayable(
                                    personId: personId!,
                                    amount: amount,
                                    description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : 'Owed',
                                    date: date,
                                  );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                            } catch (e) {
                              setSheetState(() => error = 'Failed: $e');
                            }
                          },
                    child: const Text('Add'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettleReceivableSheet(BuildContext context, WidgetRef ref, String personId, String name, double owed) {
    _showSettleSheet(
      context, ref,
      title: 'Settle up with $name',
      subtitle: '${CurrencyFormatter.format(owed)} owed to you',
      maxAmount: owed,
      switchLabel: 'They paid via bank/UPI',
      switchSubtitle: 'Records a credit to your account. Leave off if they handed you cash.',
      accountLabel: 'Credit to account',
      onConfirm: (amount, accountId) => ref.read(financeNotifierProvider.notifier).settlePerson(personId, amount, accountId: accountId),
    );
  }

  void _showSettlePayableSheet(BuildContext context, WidgetRef ref, String personId, String name, double owed) {
    _showSettleSheet(
      context, ref,
      title: 'Pay back $name',
      subtitle: '${CurrencyFormatter.format(owed)} you owe',
      maxAmount: owed,
      switchLabel: 'Pay via bank/UPI',
      switchSubtitle: 'Records a debit from your account. Leave off if you\'re paying cash.',
      accountLabel: 'Debit from account',
      onConfirm: (amount, accountId) => ref.read(financeNotifierProvider.notifier).settlePayable(personId, amount, accountId: accountId),
    );
  }

  void _showSettleSheet(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String subtitle,
    required double maxAmount,
    required String switchLabel,
    required String switchSubtitle,
    required String accountLabel,
    required Future<double> Function(double amount, String? accountId) onConfirm,
  }) {
    final amountCtrl = TextEditingController(text: maxAmount.toStringAsFixed(2));
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
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount to settle'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Partial settlements are fine — up to ${CurrencyFormatter.format(maxAmount)}.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(switchLabel, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                subtitle: Text(switchSubtitle, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                value: recordAsTransaction,
                onChanged: (v) => setSheetState(() => recordAsTransaction = v),
              ),
              if (recordAsTransaction) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedAccountId,
                  dropdownColor: AppColors.surface,
                  decoration: InputDecoration(labelText: accountLabel),
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
                    final amount = double.tryParse(amountCtrl.text.trim());
                    if (amount == null || amount <= 0) {
                      setSheetState(() => error = 'Enter a valid amount');
                      return;
                    }
                    if (recordAsTransaction && selectedAccountId == null) {
                      setSheetState(() => error = 'Select an account');
                      return;
                    }
                    try {
                      await onConfirm(amount, recordAsTransaction ? selectedAccountId : null);
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
    final unsettledTotal = participants.fold(0.0, (s, p) => s + (p.shareAmount - p.settledAmount));

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
              if (unsettledTotal > 0.01)
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
                      p.isSettled
                          ? '${peopleById[p.personId]?.name ?? 'Unknown'} • ${CurrencyFormatter.format(p.shareAmount)}'
                          : '${peopleById[p.personId]?.name ?? 'Unknown'} • ${CurrencyFormatter.format(p.shareAmount - p.settledAmount)} left'
                              '${p.settledAmount > 0 ? ' (of ${CurrencyFormatter.format(p.shareAmount)})' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: p.isSettled ? AppColors.textMuted : AppColors.textPrimary,
                        decoration: p.isSettled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (p.isSettled)
                    Text('Settled', style: TextStyle(fontSize: 11, color: AppColors.income, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
