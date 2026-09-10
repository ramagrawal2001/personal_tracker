import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/payment_reminders.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 10, 8);

  FinanceState stateWith(List<InvestmentModel> investments) => FinanceState(
        accounts: const [], categories: const [], transactions: const [],
        creditCards: const [], loans: const [], budgets: const [],
        recurringPayments: const [], investments: investments, goals: const [],
      );

  InvestmentModel sip({
    String id = 'i1',
    double amount = 5000,
    int day = 20,
    bool auto = false,
    bool deleted = false,
  }) =>
      InvestmentModel(
        id: id, name: 'Nifty 50', type: InvestmentType.mutualFundSip,
        investedAmount: 0, currentValue: 0,
        monthlySipAmount: amount, sipDay: day,
        autoInvestEnabled: auto, isDeleted: deleted,
      );

  test('a SIP gets due-soon + due-today on its sipDay', () {
    final r = PaymentReminders.compute(stateWith([sip(day: 20)]), now);
    final sipR = r.where((e) => e.title.contains('SIP')).toList();
    expect(sipR.length, 2);
    final today = sipR.firstWhere((e) => e.title.contains('today'));
    expect(today.when, DateTime(2026, 6, 20, 9));
    final soon = sipR.firstWhere((e) => e.title.contains('soon'));
    expect(soon.when, DateTime(2026, 6, 17, 10));
  });

  test('auto-invest wording differs from manual', () {
    final auto = PaymentReminders.compute(stateWith([sip(auto: true)]), now);
    expect(auto.any((e) => e.title.contains('auto-invests')), isTrue);
    final manual = PaymentReminders.compute(stateWith([sip(auto: false)]), now);
    expect(manual.any((e) => e.title.contains('SIP due')), isTrue);
    expect(manual.any((e) => e.title.contains('auto-invests')), isFalse);
  });

  test('zero SIP amount or deleted investment produces no reminders', () {
    expect(PaymentReminders.compute(stateWith([sip(amount: 0)]), now)
        .where((e) => e.id != 0), isEmpty);
    expect(PaymentReminders.compute(stateWith([sip(deleted: true)]), now)
        .where((e) => e.id != 0), isEmpty);
  });

  test('sipDay already past this month rolls to next month', () {
    final r = PaymentReminders.compute(stateWith([sip(day: 5)]), now);
    final today = r.firstWhere((e) => e.title.contains('today'));
    expect(today.when, DateTime(2026, 7, 5, 9));
  });

  test('due-soon suppressed when it is already in the past', () {
    // sipDay 11: due 11 Jun, soon = 8 Jun (before now) -> only due-today.
    final r = PaymentReminders.compute(stateWith([sip(day: 11)]), now)
        .where((e) => e.title.contains('SIP')).toList();
    expect(r.length, 1);
    expect(r.single.title.contains('today'), isTrue);
  });

  test('ids are stable, non-zero, and collision-free', () {
    final r1 = PaymentReminders.compute(stateWith([sip()]), now);
    final r2 = PaymentReminders.compute(stateWith([sip()]), now);
    expect(r1.map((e) => e.id).toList(), r2.map((e) => e.id).toList());
    expect(r1.every((e) => e.id != 0), isTrue);
    expect(r1.map((e) => e.id).toSet().length, r1.length);
  });
}
