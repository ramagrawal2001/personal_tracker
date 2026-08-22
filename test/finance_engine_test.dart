import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/core/constants/app_constants.dart';
import 'package:personal_tracker/core/database/finance_repository.dart';

void main() {
  group('FinanceEngine Tests', () {
    test('Calculated balance respects income and expense transactions', () {
      final notifier = FinanceNotifier();
      final stateBefore = notifier.state;
      final initialBalance = stateBefore.accountsWithCalculatedBalances
          .firstWhere((a) => a.id == 'acc_hdfc')
          .calculatedBalance;

      // Add ₹10,000 Income to HDFC
      notifier.addTransaction(
        accountId: 'acc_hdfc',
        type: TransactionType.income,
        amount: 10000.0,
        date: DateTime.now(),
      );

      final stateAfter = notifier.state;
      final newBalance = stateAfter.accountsWithCalculatedBalances
          .firstWhere((a) => a.id == 'acc_hdfc')
          .calculatedBalance;

      expect(newBalance, equals(initialBalance + 10000.0));
    });

    test('Credit Card Repayment reduces card outstanding without adding expense', () {
      final notifier = FinanceNotifier();
      final initialOutstanding = notifier.state.creditCards
          .firstWhere((c) => c.id == 'card_sbi')
          .currentOutstanding;

      // Pay ₹10,000 towards SBI Card
      notifier.addTransaction(
        accountId: 'acc_sbi',
        type: TransactionType.creditCardPayment,
        amount: 10000.0,
        creditCardId: 'card_sbi',
        date: DateTime.now(),
      );

      final newOutstanding = notifier.state.creditCards
          .firstWhere((c) => c.id == 'card_sbi')
          .currentOutstanding;

      expect(newOutstanding, equals(initialOutstanding - 10000.0));
    });

    test('Net worth calculation equation', () {
      final notifier = FinanceNotifier();
      final state = notifier.state;
      final netWorth = state.netWorth;
      final expected = state.totalAssets - state.totalLiabilities;

      expect(netWorth, equals(expected));
    });
  });
}
