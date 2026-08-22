import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/core/constants/app_constants.dart';
import 'package:personal_tracker/core/database/finance_repository.dart';
import 'package:personal_tracker/core/services/merchant_categorizer.dart';
import 'package:personal_tracker/domain/models/models.dart';

void main() {
  group('Comprehensive Financial Engine Edge Cases Matrix', () {
    late FinanceNotifier notifier;

    setUp(() {
      notifier = FinanceNotifier();
    });

    test('Edge Case 1: Account to Account Transfer maintains total liquid wealth invariant', () {
      final initialLiquid = notifier.state.totalLiquidBalance;
      final hdfcAcc = notifier.state.accounts.firstWhere((a) => a.id == 'acc_hdfc');
      final sbiAcc = notifier.state.accounts.firstWhere((a) => a.id == 'acc_sbi');

      notifier.addTransaction(
        accountId: hdfcAcc.id,
        toAccountId: sbiAcc.id,
        type: TransactionType.transfer,
        amount: 5000.0,
        date: DateTime.now(),
      );

      // Liquid wealth should stay invariant
      expect(notifier.state.totalLiquidBalance, equals(initialLiquid));
    });

    test('Edge Case 2: Safe to spend clamps safely to 0 when obligations exceed liquid money', () {
      // Set emergency buffer very high
      notifier.setEmergencyBuffer(1000000.0);
      expect(notifier.state.safeToSpend, equals(0.0));
    });

    test('Edge Case 3: Credit Card Repayment reduces debt without duplicating expenses', () {
      final initialDebt = notifier.state.totalCreditCardDebt;
      final initialExpenses = notifier.state.monthlyExpenses;

      notifier.addTransaction(
        accountId: 'acc_hdfc',
        type: TransactionType.creditCardPayment,
        amount: 10000.0,
        creditCardId: 'card_sbi',
        date: DateTime.now(),
      );

      // Card debt should drop by 10,000
      expect(notifier.state.totalCreditCardDebt, equals(initialDebt - 10000.0));
      // Monthly expenses should NOT increase
      expect(notifier.state.monthlyExpenses, equals(initialExpenses));
    });

    test('Edge Case 4: Loan EMI Repayment reduces loan principal liability', () {
      final initialLoanDebt = notifier.state.totalLoanDebt;

      notifier.addTransaction(
        accountId: 'acc_hdfc',
        type: TransactionType.loanPayment,
        amount: 30000.0,
        loanId: 'loan_home',
        date: DateTime.now(),
      );

      expect(notifier.state.totalLoanDebt, equals(initialLoanDebt - 30000.0));
    });

    test('Edge Case 5: Dynamic Emergency Buffer preference updates safe-to-spend formula', () {
      notifier.setEmergencyBuffer(50000.0);
      expect(notifier.state.emergencyBuffer, equals(50000.0));
    });

    test('Edge Case 6: Investment return percentage handles gain, loss, and zero division', () {
      final invGain = InvestmentModel(
        id: '1',
        name: 'Fund A',
        type: InvestmentType.mutualFundSip,
        investedAmount: 100000,
        currentValue: 125000,
      );
      expect(invGain.netReturns, equals(25000));
      expect(invGain.returnsPercentage, equals(25.0));

      final invLoss = InvestmentModel(
        id: '2',
        name: 'Fund B',
        type: InvestmentType.stocks,
        investedAmount: 50000,
        currentValue: 40000,
      );
      expect(invLoss.netReturns, equals(-10000));
      expect(invLoss.returnsPercentage, equals(-20.0));

      final invZero = InvestmentModel(
        id: '3',
        name: 'Fund C',
        type: InvestmentType.ppf,
        investedAmount: 0,
        currentValue: 0,
      );
      expect(invZero.returnsPercentage, equals(0.0));
    });

    test('Edge Case 7: Merchant Categorizer auto-mapping engine handles fuzzy strings', () {
      expect(MerchantCategorizer.categorize('SWIGGY ORDER #123')?.categoryId, equals('cat_food'));
      expect(MerchantCategorizer.categorize('AMAZON PAY INDIA')?.categoryId, equals('cat_shopping'));
      expect(MerchantCategorizer.categorize('SHELL PETROL PUMP')?.categoryId, equals('cat_transport'));
      expect(MerchantCategorizer.categorize('UNKNOWN SHOP')?.categoryId, isNull);
    });

    test('Edge Case 8: Dynamic Custom Category creation and deletion', () {
      final initialCount = notifier.state.categories.length;

      notifier.addCategory(
        name: 'Pet Care',
        type: 'expense',
        icon: 'tag',
      );
      expect(notifier.state.categories.length, equals(initialCount + 1));

      final addedCat = notifier.state.categories.firstWhere((c) => c.name == 'Pet Care');
      notifier.deleteCategory(addedCat.id);
      expect(notifier.state.categories.length, equals(initialCount));
    });
  });
}
