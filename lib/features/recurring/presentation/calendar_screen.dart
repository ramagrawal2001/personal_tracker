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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: AppDecorations.iconBadge(AppColors.accent, circle: true),
                          child: const Icon(LucideIcons.calendar, color: AppColors.accent, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _monthLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textPrimary),
                          onPressed: _prevMonth,
                          tooltip: 'Previous month',
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textPrimary),
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
                        const Icon(LucideIcons.alertCircle, color: AppColors.accent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${dueDays.length} payment${dueDays.length > 1 ? 's' : ''} scheduled in this period',
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
                return Container(
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
                        child: const Icon(LucideIcons.calendar, color: AppColors.accent, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Due ${DateFormatter.formatShort(dueDate)} • ${item.frequency.displayName}',
                              style: TextStyle(
                                color: isOverdue ? AppColors.expense : AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(item.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
