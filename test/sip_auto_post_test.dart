import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FinanceNotifier n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    n = FinanceNotifier(AppDatabase.forTesting(NativeDatabase.memory()), autoLoad: false);
    await n.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 100000);
  });

  String accId() => n.state.accounts.first.id;

  Future<void> addSip({double amount = 5000, int day = 5, bool auto = true}) =>
      n.addInvestment(
        name: 'Nifty 50', type: InvestmentType.mutualFundSip,
        investedAmount: 0, currentValue: 0,
        monthlySipAmount: amount, sipDay: day, autoInvestEnabled: auto,
      );

  final afterSipDay = DateTime(2026, 6, 10, 12); // sipDay 5 has passed
  final beforeSipDay = DateTime(2026, 6, 3, 12);

  test('posts once when due, enabled, account configured', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(afterSipDay);

    final txns = n.state.transactions.where((t) => t.tags.contains('sip-auto')).toList();
    expect(txns.length, 1);
    expect(txns.single.amount, 5000);
    expect(txns.single.accountId, accId());
    expect(txns.single.type, TransactionType.investment);
    expect(txns.single.date, DateTime(2026, 6, 5));
    expect(n.state.investments.first.lastAutoPostedMonth, '2026-06');
    // side-effect: currentValue rose by the SIP amount
    expect(n.state.investments.first.currentValue, 5000);
  });

  test('no-op before the SIP day', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(beforeSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);
    expect(n.state.investments.first.lastAutoPostedMonth, isNull);
  });

  test('no-op when disabled / zero amount / no account', () async {
    await addSip(auto: false);
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);

    await n.updateInvestment(n.state.investments.first.id, autoInvestEnabled: true, monthlySipAmount: 0);
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);

    await n.setSipDebitAccount(null);
    await n.updateInvestment(n.state.investments.first.id, monthlySipAmount: 5000);
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')), isEmpty);
  });

  test('second call in the same month is a no-op', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(afterSipDay);
    await n.processDueSipAutoPosts(afterSipDay.add(const Duration(days: 1)));
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')).length, 1);
  });

  test('ledger backstop: an existing sip-auto txn without the marker just sets the marker', () async {
    await addSip();
    await n.setSipDebitAccount(accId());
    final invId = n.state.investments.first.id;
    // simulate a crash-after-post: post the txn manually, leave marker null
    await n.addTransaction(
      accountId: accId(), type: TransactionType.investment, amount: 5000,
      date: DateTime(2026, 6, 5), investmentId: invId, tags: const ['sip-auto'],
    );
    expect(n.state.investments.first.lastAutoPostedMonth, isNull);
    await n.processDueSipAutoPosts(afterSipDay);
    expect(n.state.transactions.where((t) => t.tags.contains('sip-auto')).length, 1); // no second
    expect(n.state.investments.first.lastAutoPostedMonth, '2026-06');
  });

  test('sipDay clamps to the month length', () async {
    await addSip(day: 31);
    await n.setSipDebitAccount(accId());
    await n.processDueSipAutoPosts(DateTime(2026, 6, 30, 12)); // June has 30 days
    final t = n.state.transactions.firstWhere((t) => t.tags.contains('sip-auto'));
    expect(t.date, DateTime(2026, 6, 30));
  });
}
