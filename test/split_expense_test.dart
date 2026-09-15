// Split expenses (IOU tracking) — regression lock for
// FinanceNotifier.addSplitExpense / settleSplitParticipant / deleteSplitExpense
// / totalReceivables (part of the `flutter test` suite).
//
// The core invariant under test: the *full* bill debits the paying account
// exactly once (never reduced to "my share"), and the tracked receivable is
// pure metadata on top that never double-counts against any balance.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/domain/models/models.dart';

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

  test('the full bill debits the paying account once; the split is metadata only', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');

    await finance.addSplitExpense(
      title: 'Panipuri',
      totalAmount: 100,
      accountId: accountId,
      date: DateTime.now(),
      mode: SplitMode.equal,
      shares: {rahul.id: 50},
    );

    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 900,
        reason: 'the full ₹100 left the bank, not just the ₹50 "my share"');
    expect(finance.state.transactions.single.amount, 100);
    expect(finance.state.splitExpenses.single.title, 'Panipuri');
    expect(finance.state.splitParticipants.single.shareAmount, 50);
    expect(finance.state.totalReceivables, 50);
  });

  test('a card-charged split still bumps the card outstanding by the full amount', () async {
    await finance.addCard(
      cardType: CardType.credit, name: 'Card', bank: 'Bank', last4: '1111',
      cardholderName: 'Test', creditLimit: 50000, statementDay: 1, dueDay: 15,
    );
    await finance.addAccount(name: 'Ref', type: AccountType.savingsAccount, openingBalance: 500);
    final cardId = finance.state.creditCards.single.id;
    final accountId = finance.state.accounts.single.id;
    final priya = await finance.addPerson('Priya');

    await finance.addSplitExpense(
      title: 'Dinner',
      totalAmount: 1000,
      accountId: accountId,
      creditCardId: cardId,
      date: DateTime.now(),
      mode: SplitMode.equal,
      shares: {priya.id: 500},
    );

    expect(finance.state.creditCards.single.currentOutstanding, 1000);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 500,
        reason: 'a card charge never debits the reference account');
    expect(finance.state.totalReceivables, 500);
  });

  test('settling with recordAsTransaction credits the account and flips isSettled', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: 50},
    );
    final participant = finance.state.splitParticipants.single;
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 900);

    await finance.settleSplitParticipant(participant.id, recordAsTransaction: true, accountId: accountId);

    expect(finance.state.splitParticipants.single.isSettled, isTrue);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 950,
        reason: 'the ₹50 repayment is credited back once settled');
    expect(finance.state.totalReceivables, 0, reason: 'settled shares no longer count as owed');
  });

  test('settling without recordAsTransaction leaves the balance untouched', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: 50},
    );
    final participant = finance.state.splitParticipants.single;

    await finance.settleSplitParticipant(participant.id); // cash handoff

    expect(finance.state.splitParticipants.single.isSettled, isTrue);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 900,
        reason: 'handed over in cash — no account was ever touched by this');
    expect(finance.state.totalReceivables, 0);
  });

  test('deleteSplitExpense removes the tracking rows and reverses the underlying transaction', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: 50},
    );
    final splitId = finance.state.splitExpenses.single.id;

    await finance.deleteSplitExpense(splitId);

    expect(finance.state.splitExpenses, isEmpty);
    expect(finance.state.splitParticipants, isEmpty);
    expect(finance.state.transactions, isEmpty, reason: 'the underlying expense is removed too');
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000,
        reason: 'fully reversed');
  });

  test('totalAssets includes receivables alongside liquid balance and investments', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: 50},
    );

    // 900 liquid + 0 investments + 50 receivable = 950
    expect(finance.state.totalAssets, 950);
  });
}
