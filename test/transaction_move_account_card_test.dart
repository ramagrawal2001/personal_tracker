// Editing a transaction's account/credit-card — regression lock for
// FinanceNotifier.updateTransaction's accountId/creditCardId reassignment
// (part of the `flutter test` suite). Balances must fully reverse off the
// old account/card and apply to the new one — never double-count, never
// leave a stale outstanding behind.

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

  double balanceOf(String accountId) => finance.state.accountsWithCalculatedBalances
      .firstWhere((a) => a.id == accountId)
      .calculatedBalance;

  double outstandingOf(String cardId) =>
      finance.state.creditCards.firstWhere((c) => c.id == cardId).currentOutstanding;

  test('moving a plain expense to a different account reverses the old, applies the new', () async {
    await finance.addAccount(name: 'A', type: AccountType.savingsAccount, openingBalance: 1000);
    await finance.addAccount(name: 'B', type: AccountType.savingsAccount, openingBalance: 1000);
    final a = finance.state.accounts.firstWhere((x) => x.name == 'A').id;
    final b = finance.state.accounts.firstWhere((x) => x.name == 'B').id;

    await finance.addTransaction(
      accountId: a, type: TransactionType.expense, amount: 200, date: DateTime.now(),
    );
    final tx = finance.state.transactions.single;
    expect(balanceOf(a), 800);
    expect(balanceOf(b), 1000);

    await finance.updateTransaction(tx.id, accountId: b);

    expect(balanceOf(a), 1000, reason: 'A must get its 200 back — the expense moved off it');
    expect(balanceOf(b), 800, reason: 'B is now debited instead');
  });

  test('moving a charge from one credit card to another reverses/applies outstanding, not the balance delta', () async {
    await finance.addCard(
      cardType: CardType.credit, name: 'Card A', bank: 'Bank', last4: '1111',
      cardholderName: 'Test', creditLimit: 50000, statementDay: 1, dueDay: 15,
    );
    await finance.addCard(
      cardType: CardType.credit, name: 'Card B', bank: 'Bank', last4: '2222',
      cardholderName: 'Test', creditLimit: 50000, statementDay: 1, dueDay: 15,
    );
    await finance.addAccount(name: 'Ref', type: AccountType.savingsAccount, openingBalance: 5000);
    final cardA = finance.state.creditCards.firstWhere((c) => c.name == 'Card A').id;
    final cardB = finance.state.creditCards.firstWhere((c) => c.name == 'Card B').id;
    final ref = finance.state.accounts.single.id;

    await finance.addTransaction(
      accountId: ref, type: TransactionType.expense, amount: 1500, date: DateTime.now(), creditCardId: cardA,
    );
    final tx = finance.state.transactions.single;
    expect(outstandingOf(cardA), 1500);
    expect(outstandingOf(cardB), 0);
    expect(balanceOf(ref), 5000, reason: 'a card charge never debits the reference account');

    await finance.updateTransaction(tx.id, creditCardId: cardB);

    expect(outstandingOf(cardA), 0, reason: 'fully reversed off the old card');
    expect(outstandingOf(cardB), 1500, reason: 'fully applied to the new card');
    expect(balanceOf(ref), 5000, reason: 'still just a reference account either way');
  });

  test('clearing a charge back onto a plain account debits the account and zeroes the old card', () async {
    await finance.addCard(
      cardType: CardType.credit, name: 'Card A', bank: 'Bank', last4: '1111',
      cardholderName: 'Test', creditLimit: 50000, statementDay: 1, dueDay: 15,
    );
    await finance.addAccount(name: 'Checking', type: AccountType.savingsAccount, openingBalance: 3000);
    final cardA = finance.state.creditCards.single.id;
    final checking = finance.state.accounts.single.id;

    await finance.addTransaction(
      accountId: checking, type: TransactionType.expense, amount: 400, date: DateTime.now(), creditCardId: cardA,
    );
    final tx = finance.state.transactions.single;
    expect(outstandingOf(cardA), 400);
    expect(balanceOf(checking), 3000, reason: 'card charge, so the reference account is untouched so far');

    await finance.updateTransaction(tx.id, accountId: checking, clearCreditCardId: true);

    expect(outstandingOf(cardA), 0, reason: 'reversed — this is no longer a card charge');
    expect(balanceOf(checking), 2600, reason: 'now a plain expense against this account, so it is actually debited');
  });
}
