import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/domain/models/models.dart';
import 'test_helpers.dart';

/// Verifies the "debit card ↔ bank account" linkage: a purchase on a debit
/// card must deduct from the linked account's balance and must NOT accrue a
/// separate card outstanding the way a credit-card charge does.
void main() {
  group('Debit card linkage', () {
    late FinanceNotifier notifier;
    late String accountId;
    late String debitCardId;
    late String creditCardId;

    double accountBalance(String id) => notifier.state.accountsWithCalculatedBalances
        .firstWhere((a) => a.id == id)
        .calculatedBalance;

    double cardOutstanding(String id) =>
        notifier.state.creditCards.firstWhere((c) => c.id == id).currentOutstanding;

    setUp(() async {
      notifier = createTestFinanceNotifier();
      await notifier.addAccount(
        name: 'HDFC Savings',
        type: AccountType.savingsAccount,
        bank: 'HDFC',
        accountNumberLast4: '4242',
        openingBalance: 50000.0,
      );
      accountId = notifier.state.accounts.first.id;

      await notifier.addCard(
        cardType: CardType.debit,
        name: 'HDFC Debit',
        bank: 'HDFC',
        last4: '4242',
        cardholderName: 'Test User',
        linkedAccountId: accountId,
      );
      debitCardId = notifier.state.creditCards.firstWhere((c) => c.cardType == CardType.debit).id;

      await notifier.addCard(
        cardType: CardType.credit,
        name: 'HDFC Regalia',
        bank: 'HDFC',
        last4: '9999',
        cardholderName: 'Test User',
        creditLimit: 200000.0,
      );
      creditCardId = notifier.state.creditCards.firstWhere((c) => c.cardType == CardType.credit).id;
    });

    test('debit-card expense deducts from the linked account balance', () async {
      expect(accountBalance(accountId), 50000.0);

      await notifier.addTransaction(
        accountId: accountId, // == linkedAccountId
        type: TransactionType.expense,
        amount: 1200.0,
        creditCardId: debitCardId,
        date: DateTime.now(),
      );

      expect(accountBalance(accountId), 48800.0);
    });

    test('debit-card expense does NOT change the card outstanding', () async {
      expect(cardOutstanding(debitCardId), 0.0);

      await notifier.addTransaction(
        accountId: accountId,
        type: TransactionType.expense,
        amount: 1200.0,
        creditCardId: debitCardId,
        date: DateTime.now(),
      );

      expect(cardOutstanding(debitCardId), 0.0);
    });

    test('deleting a debit-card expense restores the balance and leaves outstanding untouched', () async {
      await notifier.addTransaction(
        accountId: accountId,
        type: TransactionType.expense,
        amount: 1200.0,
        creditCardId: debitCardId,
        date: DateTime.now(),
      );
      final txId = notifier.state.transactions.first.id;
      expect(accountBalance(accountId), 48800.0);

      await notifier.deleteTransaction(txId);

      expect(accountBalance(accountId), 50000.0);
      expect(cardOutstanding(debitCardId), 0.0);
    });

    test('regression: a credit-card expense still adds to currentOutstanding', () async {
      expect(cardOutstanding(creditCardId), 0.0);

      await notifier.addTransaction(
        accountId: accountId,
        type: TransactionType.expense,
        amount: 3000.0,
        creditCardId: creditCardId,
        date: DateTime.now(),
      );

      expect(cardOutstanding(creditCardId), 3000.0);

      // ...and deleting it reverses the outstanding.
      final txId = notifier.state.transactions.first.id;
      await notifier.deleteTransaction(txId);
      expect(cardOutstanding(creditCardId), 0.0);
    });

    test('regression: credit-card expense does not touch the source account balance path differently', () async {
      // A credit-card charge is still recorded with accountId; the existing
      // engine subtracts it from that account (unchanged behaviour). This test
      // just pins that the debit gating did not alter the credit path.
      await notifier.addTransaction(
        accountId: accountId,
        type: TransactionType.expense,
        amount: 3000.0,
        creditCardId: creditCardId,
        date: DateTime.now(),
      );
      expect(cardOutstanding(creditCardId), 3000.0);
    });
  });
}
