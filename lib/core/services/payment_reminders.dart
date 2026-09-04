import '../database/finance_repository.dart' show FinanceState;
import '../utils/currency_formatter.dart';
import '../../domain/models/models.dart';

/// One local notification to schedule. Pure data — [PaymentReminders.compute]
/// builds the full set from [FinanceState], `NotificationService` schedules it.
class ReminderSpec {
  /// Stable per (entity, kind) so a reschedule replaces rather than duplicates.
  final int id;
  final DateTime when;
  final String title;
  final String body;

  const ReminderSpec({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  @override
  String toString() => 'ReminderSpec(#$id, $when, "$title")';
}

enum _Kind { statement, dueSoon, dueToday }

/// Pure reminder rules — no plugin, fully unit-testable.
class PaymentReminders {
  PaymentReminders._();

  static const _daysBefore = 3;
  static const _reminderHour = 10; // statement + due-soon
  static const _dueHour = 9; // due-today

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Notification id for an (entity, kind) pair. Bounded 32-bit, non-zero
  /// (id 0 is the daily-log reminder).
  static int idFor(String entityId, int kind) {
    final h = Object.hash(entityId, kind) & 0x3FFFFFFF;
    return 1 + h;
  }

  /// The next date-time whose day-of-month is [day] (clamped to the month
  /// length), at [hour]:00, strictly at or after [from].
  static DateTime nextOnDay(int day, DateTime from, int hour) {
    DateTime candidate(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day.clamp(1, lastDay), hour);
    }

    var c = candidate(from.year, from.month);
    if (!c.isAfter(from)) {
      final ny = from.month == 12 ? from.year + 1 : from.year;
      final nm = from.month == 12 ? 1 : from.month + 1;
      c = candidate(ny, nm);
    }
    return c;
  }

  /// The most recent occurrence of day-of-month [day] at or before [from]
  /// (used as "current statement cycle start").
  static DateTime lastOnDay(int day, DateTime from) {
    DateTime candidate(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day.clamp(1, lastDay));
    }

    var c = candidate(from.year, from.month);
    if (c.isAfter(from)) {
      final py = from.month == 1 ? from.year - 1 : from.year;
      final pm = from.month == 1 ? 12 : from.month - 1;
      c = candidate(py, pm);
    }
    return c;
  }

  static String _amt(double v) => CurrencyFormatter.format(v);

  static List<ReminderSpec> compute(FinanceState state, DateTime now) {
    final out = <ReminderSpec>[];

    // ── Credit cards ─────────────────────────────────────────────────────
    for (final c in state.creditCards) {
      if (c.isDeleted) continue;
      if (c.cardType != CardType.credit) continue;
      final due = c.dueDay.clamp(1, 31);
      final stmt = c.statementDay.clamp(1, 31);

      // Paid this cycle? lastPaymentDate on/after the current statement date.
      final cycleStart = lastOnDay(stmt, now);
      final paidThisCycle = c.lastPaymentDate != null &&
          !c.lastPaymentDate!.isBefore(cycleStart);

      if (c.currentOutstanding > 0) {
        final s = nextOnDay(stmt, now, _reminderHour);
        out.add(ReminderSpec(
          id: idFor(c.id, _Kind.statement.index),
          when: s,
          title: '💳 ${c.bank} statement generated',
          body: 'Outstanding ${_amt(c.currentOutstanding)}. '
              'Payment due $due ${_months[(nextOnDay(due, s, _dueHour)).month - 1]}.',
        ));
      }

      if (!paidThisCycle && c.currentOutstanding > 0) {
        final dueDate = nextOnDay(due, now, _dueHour);
        final soon = dueDate.subtract(const Duration(days: _daysBefore))
            .copyWithHour(_reminderHour);
        if (soon.isAfter(now)) {
          out.add(ReminderSpec(
            id: idFor(c.id, _Kind.dueSoon.index),
            when: soon,
            title: '${c.bank} card payment due soon',
            body: '${_amt(c.currentOutstanding)} due in $_daysBefore days '
                '($due ${_months[dueDate.month - 1]}).',
          ));
        }
        out.add(ReminderSpec(
          id: idFor(c.id, _Kind.dueToday.index),
          when: dueDate,
          title: '${c.bank} card payment due today',
          body: 'Pay ${_amt(c.currentOutstanding)} to avoid interest & late fees.',
        ));
      }
    }

    // ── Loans (EMI) ─────────────────────────────────────────────────────
    for (final l in state.loans) {
      if (l.isDeleted) continue;
      if (l.outstandingAmount <= 0) continue;
      final due = l.dueDay.clamp(1, 31);
      final dueDate = nextOnDay(due, now, _dueHour);
      final soon = dueDate.subtract(const Duration(days: _daysBefore))
          .copyWithHour(_reminderHour);
      if (soon.isAfter(now)) {
        out.add(ReminderSpec(
          id: idFor(l.id, _Kind.dueSoon.index),
          when: soon,
          title: '${l.name} EMI due soon',
          body: '${_amt(l.monthlyEmi)} due in $_daysBefore days.',
        ));
      }
      out.add(ReminderSpec(
        id: idFor(l.id, _Kind.dueToday.index),
        when: dueDate,
        title: '${l.name} EMI due today',
        body: 'Pay ${_amt(l.monthlyEmi)} today.',
      ));
    }

    // ── Recurring payments ─────────────────────────────────────────────
    for (final r in state.recurringPayments) {
      if (r.isDeleted) continue;
      final d = DateTime(r.nextDueDate.year, r.nextDueDate.month, r.nextDueDate.day, _dueHour);
      if (d.isBefore(DateTime(now.year, now.month, now.day))) continue; // stale
      final soon = d.subtract(const Duration(days: _daysBefore)).copyWithHour(_reminderHour);
      if (soon.isAfter(now)) {
        out.add(ReminderSpec(
          id: idFor(r.id, _Kind.dueSoon.index),
          when: soon,
          title: '${r.title} due soon',
          body: '${_amt(r.amount)} due in $_daysBefore days.',
        ));
      }
      out.add(ReminderSpec(
        id: idFor(r.id, _Kind.dueToday.index),
        when: d,
        title: '${r.title} due today',
        body: 'Scheduled payment of ${_amt(r.amount)}.',
      ));
    }

    return out;
  }
}

extension _HourCopy on DateTime {
  DateTime copyWithHour(int hour) => DateTime(year, month, day, hour);
}
