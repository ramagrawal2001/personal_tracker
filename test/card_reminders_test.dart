import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/payment_reminders.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure reminder-rule tests for [PaymentReminders.compute] — no plugin, no db.
void main() {
  final now = DateTime(2026, 6, 10, 8); // 10 Jun 2026, 08:00

  FinanceState stateWith({
    List<CardModel> cards = const [],
    List<LoanModel> loans = const [],
    List<RecurringPaymentModel> recurring = const [],
  }) =>
      FinanceState(
        accounts: const [],
        categories: const [],
        transactions: const [],
        creditCards: cards,
        loans: loans,
        budgets: const [],
        recurringPayments: recurring,
        investments: const [],
        goals: const [],
      );

  CardModel card({
    String id = 'c1',
    int statementDay = 1,
    int dueDay = 18,
    double outstanding = 12000,
    DateTime? lastPaid,
  }) =>
      CardModel(
        id: id,
        cardType: CardType.credit,
        name: 'HDFC Regalia',
        bank: 'HDFC',
        last4: '4242',
        cardholderName: 'RAM',
        creditLimit: 200000,
        currentOutstanding: outstanding,
        statementDay: statementDay,
        dueDay: dueDay,
        lastPaymentDate: lastPaid,
      );

  test('an unpaid card gets statement + due-soon + due-today', () {
    final r = PaymentReminders.compute(stateWith(cards: [card()]), now);
    final titles = r.map((e) => e.title).toList();
    expect(titles.any((t) => t.contains('statement generated')), isTrue);
    expect(titles.any((t) => t.contains('due soon')), isTrue);
    expect(titles.any((t) => t.contains('due today')), isTrue);
    // due-today is the dueDay (18 Jun) at 09:00; due-soon is 3 days earlier.
    final dueToday = r.firstWhere((e) => e.title.contains('due today'));
    expect(dueToday.when, DateTime(2026, 6, 18, 9));
    final dueSoon = r.firstWhere((e) => e.title.contains('due soon'));
    expect(dueSoon.when, DateTime(2026, 6, 15, 10));
  });

  test('paid this cycle → due reminders suppressed, statement still scheduled', () {
    // statementDay 1 → current cycle started 1 Jun; a payment on 5 Jun counts.
    final r = PaymentReminders.compute(
      stateWith(cards: [card(lastPaid: DateTime(2026, 6, 5))]),
      now,
    );
    final titles = r.map((e) => e.title).toList();
    expect(titles.any((t) => t.contains('due soon')), isFalse);
    expect(titles.any((t) => t.contains('due today')), isFalse);
    expect(titles.any((t) => t.contains('statement generated')), isTrue);
  });

  test('a payment before this cycle does NOT suppress', () {
    final r = PaymentReminders.compute(
      stateWith(cards: [card(lastPaid: DateTime(2026, 5, 20))]), // last cycle
      now,
    );
    expect(r.map((e) => e.title).any((t) => t.contains('due today')), isTrue);
  });

  test('zero outstanding → no card reminders at all', () {
    final r = PaymentReminders.compute(stateWith(cards: [card(outstanding: 0)]), now);
    expect(r.where((e) => e.id != 0), isEmpty);
  });

  test('deleted card is ignored', () {
    final c = card().copyWith(isDeleted: true);
    expect(PaymentReminders.compute(stateWith(cards: [c]), now), isEmpty);
  });

  test('due day past this month rolls to next month', () {
    // now is 10 Jun; dueDay 5 has already passed → next is 5 Jul.
    final r = PaymentReminders.compute(stateWith(cards: [card(dueDay: 5)]), now);
    final dueToday = r.firstWhere((e) => e.title.contains('due today'));
    expect(dueToday.when, DateTime(2026, 7, 5, 9));
  });

  test('reminder ids are stable per (entity, kind) and distinct', () {
    final r1 = PaymentReminders.compute(stateWith(cards: [card()]), now);
    final r2 = PaymentReminders.compute(stateWith(cards: [card()]), now);
    expect(r1.map((e) => e.id).toList(), r2.map((e) => e.id).toList());
    expect(r1.map((e) => e.id).toSet().length, r1.length); // no collisions
    expect(r1.every((e) => e.id != 0), isTrue); // 0 reserved for the daily reminder
  });

  test('loans and recurring payments get due-soon + due-today', () {
    final loan = LoanModel(
      id: 'l1', name: 'Car Loan', provider: 'SBI',
      principalAmount: 500000, outstandingAmount: 300000,
      interestRate: 9, monthlyEmi: 12000, dueDay: 20,
      startDate: DateTime(2025, 1, 1), remainingTenureMonths: 30,
    );
    final rec = RecurringPaymentModel(
      id: 'r1', title: 'Rent', amount: 25000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 6, 25),
    );
    final r = PaymentReminders.compute(stateWith(loans: [loan], recurring: [rec]), now);
    expect(r.where((e) => e.title.contains('EMI')).length, 2);
    expect(r.where((e) => e.title.contains('Rent')).length, 2);
  });

  test('a stale (past) recurring due date is skipped', () {
    final rec = RecurringPaymentModel(
      id: 'r1', title: 'Old bill', amount: 100,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 1, 1),
    );
    expect(PaymentReminders.compute(stateWith(recurring: [rec]), now), isEmpty);
  });

  test('a payday reminder (isIncome) says "expected", not "due"', () {
    final payday = RecurringPaymentModel(
      id: 'r2', title: 'Acme Corp salary', amount: 80000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 6, 25),
      isIncome: true, companyId: 'co1',
    );
    final r = PaymentReminders.compute(stateWith(recurring: [payday]), now);
    expect(r.length, 2);
    expect(r.every((e) => e.title.contains('expected')), isTrue);
    expect(r.any((e) => e.title.contains('due')), isFalse);
  });
}
