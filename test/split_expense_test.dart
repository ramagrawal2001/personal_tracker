// Split expenses (IOU tracking) v2 — regression lock for
// FinanceNotifier.addSplitExpense / settlePerson / deleteSplitExpense /
// addPayable / settlePayable / personBalance / myShareOf (part of the
// `flutter test` suite).
//
// The core invariant under test: the *full* bill debits the paying account
// exactly once (never reduced to "my share"), and the tracked receivable/
// payable is pure metadata on top that never double-counts against any
// balance — while category/budget reporting counts only "my share".

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/domain/models/models.dart';

SplitShareInput share(double amount, {String? categoryId, String? note}) =>
    (amount: amount, categoryId: categoryId, note: note);

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
      shares: {rahul.id: share(50)},
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
      shares: {priya.id: share(500)},
    );

    expect(finance.state.creditCards.single.currentOutstanding, 1000);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 500,
        reason: 'a card charge never debits the reference account');
    expect(finance.state.totalReceivables, 500);
  });

  test('settlePerson with an account credits it and marks the share fully settled', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 900);

    final applied = await finance.settlePerson(rahul.id, 50, accountId: accountId);

    expect(applied, 50);
    expect(finance.state.splitParticipants.single.isSettled, isTrue);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 950,
        reason: 'the ₹50 repayment is credited back once settled');
    expect(finance.state.totalReceivables, 0, reason: 'settled shares no longer count as owed');
    final settleTx = finance.state.transactions.firstWhere((t) => t.type == TransactionType.refund);
    expect(settleTx.isSettlement, isTrue, reason: 'must not show up as income');
  });

  test('settlePerson without an account leaves the balance untouched (cash handoff)', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );

    final applied = await finance.settlePerson(rahul.id, 50);

    expect(applied, 50);
    expect(finance.state.splitParticipants.single.isSettled, isTrue);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 900,
        reason: 'handed over in cash — no account was ever touched by this');
    expect(finance.state.totalReceivables, 0);
    expect(finance.state.transactions.length, 1, reason: 'no settlement transaction was recorded');
  });

  test('settlePerson supports a partial settlement without splitting the row', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );

    final applied = await finance.settlePerson(rahul.id, 30);

    expect(applied, 30);
    final row = finance.state.splitParticipants.single;
    expect(row.settledAmount, 30);
    expect(row.isSettled, isFalse, reason: 'only 30 of 50 is settled');
    expect(finance.state.totalReceivables, 20, reason: 'only the remaining 20 still counts as owed');
  });

  test('settlePerson applies oldest split first across multiple splits for the same person', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Older', totalAmount: 100, accountId: accountId,
      date: DateTime(2026, 1, 1), mode: SplitMode.equal, shares: {rahul.id: share(40)},
    );
    await finance.addSplitExpense(
      title: 'Newer', totalAmount: 100, accountId: accountId,
      date: DateTime(2026, 6, 1), mode: SplitMode.equal, shares: {rahul.id: share(40)},
    );

    // 50 should fully cover the older ₹40 share, then apply ₹10 to the newer one.
    final applied = await finance.settlePerson(rahul.id, 50);
    expect(applied, 50);

    final older = finance.state.splitExpenses.firstWhere((s) => s.title == 'Older');
    final newer = finance.state.splitExpenses.firstWhere((s) => s.title == 'Newer');
    final olderRow = finance.state.splitParticipants.firstWhere((p) => p.splitExpenseId == older.id);
    final newerRow = finance.state.splitParticipants.firstWhere((p) => p.splitExpenseId == newer.id);

    expect(olderRow.isSettled, isTrue, reason: 'the older split is fully covered first');
    expect(newerRow.settledAmount, 10);
    expect(newerRow.isSettled, isFalse);
    expect(finance.state.totalReceivables, 30, reason: '30 left of the newer 40');
  });

  test('settlePerson caps at what is actually owed rather than erroring on overpayment', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );

    final applied = await finance.settlePerson(rahul.id, 500);

    expect(applied, 50, reason: 'only 50 was ever owed, the rest is not applied');
    expect(finance.state.totalReceivables, 0);
  });

  test('deleteSplitExpense removes the tracking rows and reverses the underlying transaction', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );
    final splitId = finance.state.splitExpenses.single.id;

    await finance.deleteSplitExpense(splitId);

    expect(finance.state.splitExpenses, isEmpty);
    expect(finance.state.splitParticipants, isEmpty);
    expect(finance.state.transactions, isEmpty, reason: 'the underlying expense is removed too');
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000,
        reason: 'fully reversed');
  });

  test('deleting the underlying transaction directly (not via deleteSplitExpense) cleans up the split too', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );
    final txId = finance.state.transactions.single.id;

    await finance.deleteTransaction(txId);

    expect(finance.state.transactions, isEmpty);
    expect(finance.state.splitExpenses, isEmpty, reason: 'must not survive as an orphan');
    expect(finance.state.splitParticipants, isEmpty, reason: 'must not survive as an orphan');
    expect(finance.state.totalReceivables, 0);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000);
  });

  test('a 3-way equal split never loses or duplicates a paisa (33.34/33.33/33.33, never 33.33x3)', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    final priya = await finance.addPerson('Priya');

    // resolveSplitShares (the UI's pure function) rounds each PARTICIPANT's
    // share to 33.33; the payer's implied share (myShareOf) absorbs the
    // remaining 33.34 — never three equal 33.33s, which would lose a paisa.
    await finance.addSplitExpense(
      title: 'Split 3 ways', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal,
      shares: {rahul.id: share(33.33), priya.id: share(33.33)},
    );

    final tx = finance.state.transactions.single;
    expect(finance.state.myShareOf(tx), closeTo(33.34, 0.001));
    final sum = finance.state.myShareOf(tx) +
        finance.state.splitParticipants.fold(0.0, (s, p) => s + p.shareAmount);
    expect(sum, closeTo(100.0, 0.001), reason: 'the three shares must reconcile exactly to the total bill');
  });

  test('a 7-way split reconciles exactly to the total with no accumulated rounding drift', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final people = <PersonModel>[];
    for (var i = 0; i < 6; i++) {
      people.add(await finance.addPerson('Person $i'));
    }
    // 100 / 7 = 14.2857... -> each participant rounds to 14.29.
    final each = double.parse((100 / 7).toStringAsFixed(2));
    await finance.addSplitExpense(
      title: 'Split 7 ways', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal,
      shares: {for (final p in people) p.id: share(each)},
    );

    final tx = finance.state.transactions.single;
    final participantsTotal = finance.state.splitParticipants.fold(0.0, (s, p) => s + p.shareAmount);
    final sum = finance.state.myShareOf(tx) + participantsTotal;
    expect(sum, closeTo(100.0, 0.001),
        reason: 'myShareOf is always the remainder, so the split can never drift away from the real total regardless of how many ways it is split');
  });

  test('totalAssets includes receivables alongside liquid balance and investments', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );

    // 900 liquid + 0 investments + 50 receivable = 950
    expect(finance.state.totalAssets, 950);
  });

  // ── Payables — the "I owe them" direction ────────────────────────────────

  test('addPayable + settlePayable with an account debits it and marks fully settled', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final aniket = await finance.addPerson('Aniket');
    await finance.addPayable(personId: aniket.id, amount: 200, description: 'Movie tickets', date: DateTime.now());

    expect(finance.state.totalPayables, 200);
    expect(finance.state.totalLiabilities, 200, reason: 'payables count as a liability');
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000,
        reason: 'owing money does not touch the balance until you actually pay it');

    final applied = await finance.settlePayable(aniket.id, 200, accountId: accountId);

    expect(applied, 200);
    expect(finance.state.payables.single.isSettled, isTrue);
    expect(finance.state.totalPayables, 0);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 800,
        reason: 'paying them back really did leave the account');
    final settleTx = finance.state.transactions.firstWhere((t) => t.type == TransactionType.expense);
    expect(settleTx.isSettlement, isTrue, reason: 'must not show up as spending');
  });

  test('settlePayable without an account leaves the balance untouched (cash handoff)', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final aniket = await finance.addPerson('Aniket');
    await finance.addPayable(personId: aniket.id, amount: 200, description: 'Movie tickets', date: DateTime.now());

    await finance.settlePayable(aniket.id, 200);

    expect(finance.state.payables.single.isSettled, isTrue);
    expect(finance.state.accountsWithCalculatedBalances.single.calculatedBalance, 1000);
    expect(finance.state.transactions, isEmpty);
  });

  test('deletePayable removes it from totalPayables', () async {
    final aniket = await finance.addPerson('Aniket');
    await finance.addPayable(personId: aniket.id, amount: 200, description: 'Movie tickets', date: DateTime.now());
    final id = finance.state.payables.single.id;

    await finance.deletePayable(id);

    expect(finance.state.payables, isEmpty);
    expect(finance.state.totalPayables, 0);
  });

  test('personBalance nets receivables against payables for the same person', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final kunal = await finance.addPerson('Kunal');
    await finance.addSplitExpense(
      title: 'Lunch', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {kunal.id: share(60)},
    );
    await finance.addPayable(personId: kunal.id, amount: 25, description: 'Movie', date: DateTime.now());

    expect(finance.state.personBalance(kunal.id), 35, reason: '60 owed to you minus 25 you owe them');
    expect(finance.state.allPersonBalances(), {kunal.id: 35});
  });

  // ── Reporting: category totals/budgets count only "my share" ────────────

  test('myShareOf returns the full amount for an ordinary transaction', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    await finance.addTransaction(accountId: accountId, type: TransactionType.expense, amount: 300, date: DateTime.now());
    expect(finance.state.myShareOf(finance.state.transactions.single), 300);
  });

  test('myShareOf returns only the payer\'s share for a split expense', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Groceries', totalAmount: 500, accountId: accountId, categoryId: 'cat_groceries',
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(250)},
    );
    expect(finance.state.myShareOf(finance.state.transactions.single), 250);
  });

  test('monthlyExpenses counts only my share of a split bill, not the full amount', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Groceries', totalAmount: 500, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(250)},
    );
    expect(finance.state.monthlyExpenses, 250, reason: 'not the full ₹500');
  });

  test('monthlyIncome and monthlyExpenses exclude isSettlement transactions', () async {
    await finance.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 1000);
    final accountId = finance.state.accounts.single.id;
    final rahul = await finance.addPerson('Rahul');
    await finance.addSplitExpense(
      title: 'Panipuri', totalAmount: 100, accountId: accountId,
      date: DateTime.now(), mode: SplitMode.equal, shares: {rahul.id: share(50)},
    );
    await finance.settlePerson(rahul.id, 50, accountId: accountId); // creates a `refund`, isSettlement: true

    expect(finance.state.monthlyIncome, 0, reason: 'a friend paying back their share is not income');

    final aniket = await finance.addPerson('Aniket');
    await finance.addPayable(personId: aniket.id, amount: 40, description: 'Loan', date: DateTime.now());
    await finance.settlePayable(aniket.id, 40, accountId: accountId); // creates an `expense`, isSettlement: true

    expect(finance.state.monthlyExpenses, 50, reason: 'only the original ₹50 share — the ₹40 settlement is a transfer, not spending');
  });
}
