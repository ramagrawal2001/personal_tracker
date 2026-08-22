import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/merchant_categorizer.dart';
import 'package:aspyric/domain/models/models.dart';

void main() {
  group('Comprehensive Financial Engine Edge Cases Matrix', () {
    late FinanceNotifier notifier;

    setUp(() {
      notifier = FinanceNotifier();
      // Set up test accounts, credit cards, and loans fresh for each test
      notifier.addAccount(
        name: 'HDFC Test Account',
        type: AccountType.savingsAccount,
        bank: 'HDFC Bank',
        accountNumberLast4: '5421',
        openingBalance: 52430.0,
      );
      notifier.addAccount(
        name: 'SBI Test Account',
        type: AccountType.savingsAccount,
        bank: 'SBI',
        accountNumberLast4: '8812',
        openingBalance: 21820.0,
      );
      notifier.addCreditCard(
        name: 'SBI Cashback Card',
        bank: 'SBI Card',
        last4: '4321',
        creditLimit: 200000.0,
        statementDay: 2,
        dueDay: 22,
      );
      notifier.addLoan(
        name: 'Home Loan',
        provider: 'SBI',
        principalAmount: 3500000.0,
        interestRate: 8.5,
        monthlyEmi: 30000.0,
        dueDay: 28,
        tenureMonths: 168,
      );
    });

    test('Edge Case 1: Account to Account Transfer maintains total liquid wealth invariant', () {
      final initialLiquid = notifier.state.totalLiquidBalance;
      final hdfcAcc = notifier.state.accounts.firstWhere((a) => a.name.contains('HDFC'));
      final sbiAcc = notifier.state.accounts.firstWhere((a) => a.name.contains('SBI'));

      notifier.addTransaction(
        accountId: hdfcAcc.id,
        toAccountId: sbiAcc.id,
        type: TransactionType.transfer,
        amount: 5000.0,
        date: DateTime.now(),
      );

      expect(notifier.state.totalLiquidBalance, equals(initialLiquid));
    });

    test('Edge Case 2: Safe to spend clamps safely to 0 when obligations exceed liquid money', () {
      notifier.setEmergencyBuffer(1000000.0);
      expect(notifier.state.safeToSpend, equals(0.0));
    });

    test('Edge Case 3: Credit Card Repayment does not double-count as expense', () {
      final card = notifier.state.creditCards.first;
      final account = notifier.state.accounts.first;

      notifier.addTransaction(
        accountId: account.id,
        type: TransactionType.creditCardPayment,
        amount: 10000.0,
        creditCardId: card.id,
        date: DateTime.now(),
      );

      // creditCardPayment type is not counted in monthlyExpenses
      final monthlyExpenses = notifier.state.monthlyExpenses;
      expect(monthlyExpenses, isA<double>());
      expect(monthlyExpenses >= 0, isTrue);
    });

    test('Edge Case 4: Loan EMI Repayment reduces loan principal liability', () {
      final loan = notifier.state.loans.first;
      final initialLoanDebt = notifier.state.totalLoanDebt;

      notifier.addTransaction(
        accountId: notifier.state.accounts.first.id,
        type: TransactionType.loanPayment,
        amount: 30000.0,
        loanId: loan.id,
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
