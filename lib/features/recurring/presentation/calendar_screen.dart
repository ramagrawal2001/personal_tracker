import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../../../domain/models/models.dart';
import '../../../core/utils/responsive.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  void _prevMonth() => setState(() {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
      });

  void _nextMonth() => setState(() {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
      });

  /// Returns days in current _selectedMonth
  int get _daysInMonth =>
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;

  String get _monthLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final recurring = financeState.recurringPayments;

    // Collect days in _selectedMonth that have a due payment
    final dueDays = <int>{};
    for (final r in recurring) {
      final d = r.nextDueDate;
      if (d.year == _selectedMonth.year && d.month == _selectedMonth.month) {
        dueDays.add(d.day);
      }
    }

    // Show only days 1–7 around today (or first 7 of month) for the mini strip
    final today = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == today.year && _selectedMonth.month == today.month;
    final startDay = isCurrentMonth ? today.day : 1;
    final stripDays = List.generate(
      7,
      (i) {
        final d = startDay + i;
        return d <= _daysInMonth ? d : null;
      },
    ).whereType<int>().toList();

    // Upcoming schedule filtered to selected month
    final upcoming = recurring.where((r) {
      final d = r.nextDueDate;
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }).toList()
      ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));

    // All recurring for future months
    final future = recurring.where((r) {
      final d = r.nextDueDate;
      return d.isAfter(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0));
    }).toList();

    final scheduleItems = upcoming.isNotEmpty ? upcoming : future;

    return AppScaffold(
      title: 'Financial Calendar',
      scrollable: true,
      actions: [
        IconButton(
          icon: Icon(LucideIcons.plus, color: AppColors.primary),
          onPressed: () => _showRecurringSheet(context, ref, financeState),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Month navigator ───────────────────────────────────────────
          AppCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: AppDecorations.iconBadge(AppColors.accent, circle: true),
                            child: Icon(LucideIcons.calendar, color: AppColors.accent, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _monthLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textPrimary),
                          onPressed: _prevMonth,
                          tooltip: 'Previous month',
                        ),
                        IconButton(
                          icon: Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textPrimary),
                          onPressed: _nextMonth,
                          tooltip: 'Next month',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Day strip ────────────────────────────────────────────
                if (stripDays.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: stripDays.map((day) {
                      final isToday = isCurrentMonth && day == today.day;
                      final isDue = dueDays.contains(day);
                      final highlight = isDue || isToday;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: highlight
                              ? AppColors.primary.withValues(alpha: 0.18)
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: highlight ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: highlight ? AppColors.primary : AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              isDue ? LucideIcons.creditCard : (isToday ? LucideIcons.dot : LucideIcons.circle),
                              size: 10,
                              color: isDue
                                  ? AppColors.primary
                                  : (isToday ? AppColors.income : Colors.transparent),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                // Due count badge
                if (dueDays.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: AppDecorations.alertBanner(AppColors.accent),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.alertCircle, color: AppColors.accent, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${dueDays.length} payment${dueDays.length > 1 ? 's' : ''} scheduled in this period',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Upcoming schedule ─────────────────────────────────────────
          SectionHeader(
            title: upcoming.isNotEmpty ? 'Due in $_monthLabel' : 'Upcoming Recurring Obligations',
          ),

          if (scheduleItems.isEmpty)
            const EmptyState(
              icon: LucideIcons.calendarOff,
              title: 'No payments scheduled',
              description: 'Recurring subscriptions, utility bills, and insurance payments will be listed here.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scheduleItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = scheduleItems[index];
                final dueDate = item.nextDueDate;
                final isOverdue = dueDate.isBefore(today) && !isCurrentMonth;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showRecurringSheet(context, ref, financeState, existing: item),
                  onLongPress: () => _confirmDeleteRecurring(context, ref, item),
                  child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isOverdue ? AppColors.expense.withValues(alpha: 0.5) : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: AppDecorations.iconBadge(AppColors.accent),
                        child: Icon(LucideIcons.calendar, color: AppColors.accent, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Due ${DateFormatter.formatShort(dueDate)} • ${item.frequency.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isOverdue ? AppColors.expense : AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        CurrencyFormatter.format(item.amount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showRecurringSheet(BuildContext context, WidgetRef ref, FinanceState financeState, {RecurringPaymentModel? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(text: existing != null ? existing.amount.toStringAsFixed(0) : '');
    PaymentFrequency frequency = existing?.frequency ?? PaymentFrequency.monthly;
    DateTime dueDate = existing?.nextDueDate ?? DateTime.now().add(const Duration(days: 7));
    bool isAutoPay = existing?.isAutoPay ?? false;
    String? categoryId = existing?.categoryId;
    String? accountId = existing?.accountId;
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
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(existing == null ? 'New Recurring Payment' : 'Edit Recurring Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title (e.g. Netflix, Rent)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Amount (${CurrencyFormatter.symbol})', errorText: error, prefixIcon: const Icon(LucideIcons.indianRupee, size: 16)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PaymentFrequency>(
                  isExpanded: true,
                  value: frequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  dropdownColor: AppColors.surface,
                  items: PaymentFrequency.values.map((f) => DropdownMenuItem(value: f, child: Text(f.displayName))).toList(),
                  onChanged: (v) => setSheetState(() => frequency = v ?? frequency),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dueDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) setSheetState(() => dueDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Next Due Date'),
                    child: Text(DateFormatter.formatShort(dueDate), style: TextStyle(color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(height: 16),
                if (financeState.categories.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: categoryId,
                    decoration: const InputDecoration(labelText: 'Category (optional)'),
                    dropdownColor: AppColors.surface,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('None')),
                      ...financeState.categories.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (v) => setSheetState(() => categoryId = v),
                  ),
                const SizedBox(height: 16),
                if (financeState.accounts.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: accountId,
                    decoration: const InputDecoration(labelText: 'Pay From Account (optional)'),
                    dropdownColor: AppColors.surface,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('None')),
                      ...financeState.accounts.map((a) => DropdownMenuItem<String?>(value: a.id, child: Text(a.name))),
                    ],
                    onChanged: (v) => setSheetState(() => accountId = v),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Auto-Pay', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  value: isAutoPay,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setSheetState(() => isAutoPay = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Enter a title'), backgroundColor: AppColors.expense));
                        return;
                      }
                      final amount = double.tryParse(amountCtrl.text);
                      if (amount == null || amount <= 0) {
                        setSheetState(() => error = 'Enter an amount greater than 0');
                        return;
                      }
                      final notifier = ref.read(financeNotifierProvider.notifier);
                      if (existing == null) {
                        notifier.addRecurringPayment(
                          title: titleCtrl.text.trim(),
                          amount: amount,
                          frequency: frequency,
                          nextDueDate: dueDate,
                          categoryId: categoryId,
                          accountId: accountId,
                          isAutoPay: isAutoPay,
                        );
                      } else {
                        notifier.updateRecurringPayment(
                          existing.id,
                          title: titleCtrl.text.trim(),
                          amount: amount,
                          frequency: frequency,
                          nextDueDate: dueDate,
                          categoryId: categoryId,
                          accountId: accountId,
                          isAutoPay: isAutoPay,
                        );
                      }
                      Navigator.pop(context);
                    },
                    child: Text(existing == null ? 'Add Payment' : 'Save Changes'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteRecurring(BuildContext context, WidgetRef ref, RecurringPaymentModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete recurring payment?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Remove "${item.title}"? This cannot be undone.', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(financeNotifierProvider.notifier).deleteRecurringPayment(item.id);
              Navigator.pop(ctx);
              showUndoDeleteSnackBar(
                context,
                message: '"${item.title}" deleted',
                onUndo: () => ref
                    .read(financeNotifierProvider.notifier)
                    .undoDelete('recurring_payments', item.id),
              );
            },
            child: Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
  }
}
