import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceState stateWith({
    List<RecurringPaymentModel> recurring = const [],
    List<InvestmentModel> investments = const [],
  }) =>
      FinanceState(
        accounts: const [], categories: const [], transactions: const [],
        creditCards: const [], loans: const [], budgets: const [],
        recurringPayments: recurring, investments: investments, goals: const [],
      );

  final anchor = DateTime(2026, 2, 1); // Feb 2026 (28 days)

  test('merges recurring + SIP, sorted by date', () {
    final rec = RecurringPaymentModel(
      id: 'r1', title: 'Rent', amount: 25000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 2, 5),
    );
    final inv = InvestmentModel(
      id: 'i1', name: 'Nifty 50', type: InvestmentType.mutualFundSip,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 5000, sipDay: 3,
    );
    final out = stateWith(recurring: [rec], investments: [inv]).upcomingObligations(anchor);
    expect(out.map((o) => o.kind), [ObligationKind.sip, ObligationKind.recurring]);
    expect(out.first.id, 'sip_i1');
    expect(out.first.sourceId, 'i1');
    expect(out.first.date, DateTime(2026, 2, 3));
    expect(out.first.amount, 5000);
    expect(out.first.isIncome, isFalse);
    expect(out.last.title, 'Rent');
  });

  test('SIP day is clamped to the anchor month length', () {
    final inv = InvestmentModel(
      id: 'i1', name: 'X', type: InvestmentType.mutualFundSip,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 1000, sipDay: 31,
    );
    final out = stateWith(investments: [inv]).upcomingObligations(anchor);
    expect(out.single.date, DateTime(2026, 2, 28));
  });

  test('deleted / zero-amount SIPs and deleted recurring are excluded', () {
    final inv0 = InvestmentModel(id: 'i0', name: 'z', type: InvestmentType.stocks,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 0, sipDay: 5);
    final invD = InvestmentModel(id: 'iD', name: 'z', type: InvestmentType.stocks,
      investedAmount: 0, currentValue: 0, monthlySipAmount: 500, sipDay: 5, isDeleted: true);
    final recD = RecurringPaymentModel(id: 'rD', title: 'gone', amount: 1,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 2, 9), isDeleted: true);
    expect(stateWith(recurring: [recD], investments: [inv0, invD]).upcomingObligations(anchor), isEmpty);
  });

  test('income recurring keeps its isIncome flag', () {
    final pay = RecurringPaymentModel(id: 'p', title: 'Salary', amount: 90000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime(2026, 2, 25), isIncome: true);
    final out = stateWith(recurring: [pay]).upcomingObligations(anchor);
    expect(out.single.isIncome, isTrue);
  });
}
