import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';

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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'FINANCIAL CALENDAR',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Month navigator ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _monthLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.chevronLeft, size: 20, color: AppColors.textPrimary),
                            onPressed: _prevMonth,
                            tooltip: 'Previous month',
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.chevronRight, size: 20, color: AppColors.textPrimary),
                            onPressed: _nextMonth,
                            tooltip: 'Next month',
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

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
                                ? AppColors.primary.withValues(alpha: 0.2)
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
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.alertCircle, color: AppColors.accent, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${dueDays.length} payment${dueDays.length > 1 ? 's' : ''} due this month',
                            style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
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
            Text(
              upcoming.isNotEmpty
                  ? 'Due in $_monthLabel'
                  : 'Upcoming Payments',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),

            if (scheduleItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Icon(LucideIcons.calendarOff, size: 40, color: AppColors.textMuted.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text('No recurring payments scheduled', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: scheduleItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = scheduleItems[index];
                  final dueDate = item.nextDueDate;
                  final isOverdue = dueDate.isBefore(today) && !isCurrentMonth;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isOverdue ? AppColors.expense.withValues(alpha: 0.4) : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.calendar, color: AppColors.accent, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                    fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Due ${DateFormatter.formatShort(dueDate)} • ${item.frequency.displayName}',
                                style: TextStyle(
                                    color: isOverdue ? AppColors.expense : AppColors.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(item.amount),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 16),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
