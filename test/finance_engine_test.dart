import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/core/constants/app_constants.dart';
import 'package:personal_tracker/core/database/finance_repository.dart';

void main() {
  group('FinanceEngine Tests', () {
    late FinanceNotifier notifier;
    late String hdfcId;
    late String sbiId;
    late String cardId;

    setUp(() {
      notifier = FinanceNotifier();
      // Create test accounts
      notifier.addAccount(
        name: 'HDFC Test',
        type: AccountType.savingsAccount,
        bank: 'HDFC',
        accountNumberLast4: '5421',
        openingBalance: 52430.0,
      );
      notifier.addAccount(
        name: 'SBI Test',
        type: AccountType.savingsAccount,
        bank: 'SBI',
        accountNumberLast4: '8812',
        openingBalance: 21820.0,
      );
      notifier.addCreditCard(
        name: 'SBI Card',
        bank: 'SBI Card',
        last4: '4321',
        creditLimit: 200000.0,
        statementDay: 2,
        dueDay: 22,
      );
      // Add some outstanding to the credit card via expense
      hdfcId = notifier.state.accounts.firstWhere((a) => a.name.contains('HDFC')).id;
      sbiId = notifier.state.accounts.firstWhere((a) => a.name.contains('SBI')).id;
      cardId = notifier.state.creditCards.first.id;
    });

    test('Calculated balance respects income and expense transactions', () {
      final initialBalance = notifier.state.accountsWithCalculatedBalances
          .firstWhere((a) => a.id == hdfcId)
          .calculatedBalance;

      // Add ₹10,000 Income to HDFC
      notifier.addTransaction(
        accountId: hdfcId,
        type: TransactionType.income,
        amount: 10000.0,
        date: DateTime.now(),
      );

      final newBalance = notifier.state.accountsWithCalculatedBalances
          .firstWhere((a) => a.id == hdfcId)
          .calculatedBalance;

      expect(newBalance, equals(initialBalance + 10000.0));
    });

    test('Credit Card Repayment reduces card outstanding without adding expense', () {
      // First add some charges to the card
      notifier.addTransaction(
        accountId: sbiId,
        type: TransactionType.expense,
        amount: 47700.0,
        categoryId: 'cat_shopping',
        creditCardId: cardId,
        date: DateTime.now().subtract(const Duration(days: 5)),
      );

      final initialOutstanding = notifier.state.creditCards
          .firstWhere((c) => c.id == cardId)
          .currentOutstanding;

      // Pay ₹10,000 towards the card
      notifier.addTransaction(
        accountId: sbiId,
        type: TransactionType.creditCardPayment,
        amount: 10000.0,
        creditCardId: cardId,
        date: DateTime.now(),
      );

      final newOutstanding = notifier.state.creditCards
          .firstWhere((c) => c.id == cardId)
          .currentOutstanding;

      expect(newOutstanding, equals(initialOutstanding - 10000.0));
    });

    test('Net worth calculation equation', () {
      final state = notifier.state;
      final netWorth = state.netWorth;
      final expected = state.totalAssets - state.totalLiabilities;
      expect(netWorth, equals(expected));
    });

    test('New user starts with empty state (no hardcoded data)', () {
      expect(notifier.state.transactions, isEmpty);
      expect(notifier.state.creditCards.length, equals(1)); // only our test card from setUp
      expect(notifier.state.loans, isEmpty);
      expect(notifier.state.investments, isEmpty);
      expect(notifier.state.goals, isEmpty);
    });
  });
}
