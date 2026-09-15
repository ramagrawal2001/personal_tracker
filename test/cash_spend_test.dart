// Cash as a "Pay With" option — regression lock (part of the `flutter test`
// suite). A cash spend must never touch any account balance, exactly like a
// credit-card charge or a salary PF leg (isExternalToAccount) already don't.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FinanceNotifier finance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    finance = FinanceNotifier(db, autoLoad: false);
  });

  tearDown(() async {
    await db.close();
  });

  test('a cash spend does not debit the reference account', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;

    await finance.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 300,
      date: DateTime.now(),
      isCashSpend: true,
    );

    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000,
        reason: 'cash spends are tracked for reporting only, never against a bank balance');
  });

  test('a plain (non-cash) expense on the same account still debits normally', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;

    await finance.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 300,
      date: DateTime.now(),
    );

    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 700);
  });

  test('editing a transaction to toggle isCashSpend recomputes the balance', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    await finance.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 300,
      date: DateTime.now(),
    );
    final tx = finance.state.transactions.single;
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 700);

    await finance.updateTransaction(tx.id, isCashSpend: true);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000,
        reason: 'flipping to cash reverses the debit — no manual reversal needed, it is purely derived');

    await finance.updateTransaction(tx.id, isCashSpend: false);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 700);
  });
}
