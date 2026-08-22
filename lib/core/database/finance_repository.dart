import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../../domain/models/models.dart';

const _uuid = Uuid();

class FinanceState {
  final List<AccountModel> accounts;
  final List<CategoryModel> categories;
  final List<TransactionModel> transactions;
  final List<CreditCardModel> creditCards;
  final List<LoanModel> loans;
  final List<BudgetModel> budgets;
  final List<RecurringPaymentModel> recurringPayments;
  final List<InvestmentModel> investments;
  final List<GoalModel> goals;
  final double emergencyBuffer;
  final String currencySymbol;
  final bool isBiometricEnabled;
  final bool isRoundUpEnabled;
  final bool isAutoBackupEnabled;

  FinanceState({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.creditCards,
    required this.loans,
    required this.budgets,
    required this.recurringPayments,
    required this.investments,
    required this.goals,
    this.emergencyBuffer = 20000.0,
    this.currencySymbol = '₹',
    this.isBiometricEnabled = false,
    this.isRoundUpEnabled = false,
    this.isAutoBackupEnabled = false,
  });




  double get totalInvestedAmount {
    return investments.fold(0.0, (sum, i) => sum + i.investedAmount);
  }

  double get totalInvestmentCurrentValue {
    return investments.fold(0.0, (sum, i) => sum + i.currentValue);
  }

  double get totalMonthlySipAmount {
    return investments.fold(0.0, (sum, i) => sum + i.monthlySipAmount);
  }

  /// Total Assets = Liquid Money + Investment Portfolio Value
  double get totalAssets {
    double liquid = totalLiquidBalance;
    double portfolio = totalInvestmentCurrentValue;
    return liquid + portfolio;
  }


  // --- Dynamic Financial Calculations ---

  /// Dynamic Balance Calculation rule:
  /// Calculated Balance = Opening Balance + Income + Transfers In - Expenses - Transfers Out - Payments
  List<AccountModel> get accountsWithCalculatedBalances {
    return accounts.map((acc) {
      double calc = acc.openingBalance;

      for (var tx in transactions) {
        if (tx.accountId == acc.id) {
          if (tx.type == TransactionType.income || tx.type == TransactionType.refund) {
            calc += tx.amount;
          } else if (tx.type == TransactionType.expense ||
              tx.type == TransactionType.transfer ||
              tx.type == TransactionType.creditCardPayment ||
              tx.type == TransactionType.loanPayment ||
              tx.type == TransactionType.investment) {
            calc -= tx.amount;
          }
        }

        // Transfers received
        if (tx.toAccountId == acc.id) {
          calc += tx.amount;
        }
      }

      return acc.copyWith(calculatedBalance: calc);
    }).toList();
  }

  /// Total Liquid Money across active accounts & cash
  double get totalLiquidBalance {
    return accountsWithCalculatedBalances
        .where((a) => a.isActive && (a.type == AccountType.bankAccount || a.type == AccountType.savingsAccount || a.type == AccountType.cash || a.type == AccountType.wallet))
        .fold(0.0, (sum, a) => sum + a.calculatedBalance);
  }

  /// Total Credit Card Debt
  double get totalCreditCardDebt {
    return creditCards.fold(0.0, (sum, c) => sum + c.currentOutstanding);
  }

  /// Total Loan Debt
  double get totalLoanDebt {
    return loans.fold(0.0, (sum, l) => sum + l.outstandingAmount);
  }

  /// Total Monthly EMI across all active loans
  double get totalMonthlyEmi {
    return loans.fold(0.0, (sum, l) => sum + l.monthlyEmi);
  }

  /// Total Liabilities = Credit Cards + Loans
  double get totalLiabilities => totalCreditCardDebt + totalLoanDebt;

  /// Net Worth = Total Assets - Total Liabilities
  double get netWorth => totalAssets - totalLiabilities;


  /// Monthly Income (Current Month)
  double get monthlyIncome {
    final now = DateTime.now();
    return transactions
        .where((t) => (t.type == TransactionType.income || t.type == TransactionType.refund) && t.date.month == now.month && t.date.year == now.year)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Monthly Expenses (Current Month)
  double get monthlyExpenses {
    final now = DateTime.now();
    return transactions
        .where((t) => t.type == TransactionType.expense && t.date.month == now.month && t.date.year == now.year)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Upcoming Payments total for next 30 days
  double get upcomingPaymentsTotal {
    return recurringPayments.fold(0.0, (sum, p) => sum + p.amount);
  }

  /// Safe To Spend = Liquid Balance - Upcoming Obligations - Dynamic Emergency Buffer
  double get safeToSpend {
    final safe = totalLiquidBalance - upcomingPaymentsTotal - emergencyBuffer;
    return safe > 0 ? safe : 0.0;
  }


  FinanceState copyWith({
    List<AccountModel>? accounts,
    List<CategoryModel>? categories,
    List<TransactionModel>? transactions,
    List<CreditCardModel>? creditCards,
    List<LoanModel>? loans,
    List<BudgetModel>? budgets,
    List<RecurringPaymentModel>? recurringPayments,
    List<InvestmentModel>? investments,
    List<GoalModel>? goals,
    double? emergencyBuffer,
    String? currencySymbol,
    bool? isBiometricEnabled,
    bool? isRoundUpEnabled,
    bool? isAutoBackupEnabled,
  }) {
    return FinanceState(
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      creditCards: creditCards ?? this.creditCards,
      loans: loans ?? this.loans,
      budgets: budgets ?? this.budgets,
      recurringPayments: recurringPayments ?? this.recurringPayments,
      investments: investments ?? this.investments,
      goals: goals ?? this.goals,
      emergencyBuffer: emergencyBuffer ?? this.emergencyBuffer,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isRoundUpEnabled: isRoundUpEnabled ?? this.isRoundUpEnabled,
      isAutoBackupEnabled: isAutoBackupEnabled ?? this.isAutoBackupEnabled,
    );
  }



}

class FinanceNotifier extends StateNotifier<FinanceState> {
  FinanceNotifier() : super(_emptyState());

  /// Default categories always available to every user
  static List<CategoryModel> _defaultCategories() {
    return [
      CategoryModel(id: 'cat_food', name: 'Food & Dining', type: 'expense', icon: 'utensils', colorHex: '0xFFF59E0B'),
      CategoryModel(id: 'cat_groceries', name: 'Groceries', parentId: 'cat_food', type: 'expense', icon: 'shopping-bag', colorHex: '0xFF10B981'),
      CategoryModel(id: 'cat_transport', name: 'Transport & Fuel', type: 'expense', icon: 'car', colorHex: '0xFF3B82F6'),
      CategoryModel(id: 'cat_shopping', name: 'Shopping', type: 'expense', icon: 'shopping-cart', colorHex: '0xFFEC4899'),
      CategoryModel(id: 'cat_housing', name: 'Housing & Rent', type: 'expense', icon: 'home', colorHex: '0xFF8B5CF6'),
      CategoryModel(id: 'cat_bills', name: 'Bills & Utilities', type: 'expense', icon: 'zap', colorHex: '0xFF6366F1'),
      CategoryModel(id: 'cat_salary', name: 'Salary', type: 'income', icon: 'briefcase', colorHex: '0xFF10B981'),
      CategoryModel(id: 'cat_freelance', name: 'Freelancing', type: 'income', icon: 'laptop', colorHex: '0xFF0EA5E9'),
      CategoryModel(id: 'cat_investment', name: 'Investment / SIP', type: 'expense', icon: 'trending-up', colorHex: '0xFF8B5CF6'),
    ];
  }

  /// Clean empty state — every user starts fresh with no data
  static FinanceState _emptyState() {
    return FinanceState(
      accounts: [],
      categories: _defaultCategories(),
      transactions: [],
      creditCards: [],
      loans: [],
      budgets: [],
      recurringPayments: [],
      investments: [],
      goals: [],
    );
  }



  // --- Actions & State Modifiers ---

  void addTransaction({
    required String accountId,
    String? toAccountId,
    required TransactionType type,
    required double amount,
    String? categoryId,
    String? merchant,
    required DateTime date,
    String? description,
    String? notes,
    List<String> tags = const [],
    String? creditCardId,
    String? loanId,
    bool isOnline = true,
  }) {
    final newTx = TransactionModel(
      id: _uuid.v4(),
      accountId: accountId,
      toAccountId: toAccountId,
      type: type,
      amount: amount,
      categoryId: categoryId,
      merchant: merchant,
      date: date,
      description: description,
      notes: notes,
      tags: tags,
      creditCardId: creditCardId,
      loanId: loanId,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pending,
      createdAt: DateTime.now(),
    );

    // Credit card outstanding management
    List<CreditCardModel> updatedCards = List.from(state.creditCards);
    if (creditCardId != null) {
      final cardIdx = updatedCards.indexWhere((c) => c.id == creditCardId);
      if (cardIdx != -1) {
        final card = updatedCards[cardIdx];
        double newOutstanding = card.currentOutstanding;

        if (type == TransactionType.creditCardPayment) {
          // Payment reduces outstanding
          newOutstanding = (card.currentOutstanding - amount).clamp(0.0, card.creditLimit);
        } else if (type == TransactionType.expense) {
          // Spending charges to card increases outstanding
          newOutstanding = (card.currentOutstanding + amount).clamp(0.0, card.creditLimit);
        }

        updatedCards[cardIdx] = CreditCardModel(
          id: card.id,
          name: card.name,
          bank: card.bank,
          last4: card.last4,
          creditLimit: card.creditLimit,
          currentOutstanding: newOutstanding,
          statementDay: card.statementDay,
          dueDay: card.dueDay,
          linkedAccountId: card.linkedAccountId,
        );
      }
    }


    // If loan payment transfer
    List<LoanModel> updatedLoans = List.from(state.loans);
    if (type == TransactionType.loanPayment && loanId != null) {
      final loanIdx = updatedLoans.indexWhere((l) => l.id == loanId);
      if (loanIdx != -1) {
        final loan = updatedLoans[loanIdx];
        final newOutstanding = (loan.outstandingAmount - amount).clamp(0.0, loan.principalAmount);
        updatedLoans[loanIdx] = LoanModel(
          id: loan.id,
          name: loan.name,
          provider: loan.provider,
          principalAmount: loan.principalAmount,
          outstandingAmount: newOutstanding,
          interestRate: loan.interestRate,
          monthlyEmi: loan.monthlyEmi,
          dueDay: loan.dueDay,
          startDate: loan.startDate,
          remainingTenureMonths: loan.remainingTenureMonths > 0 ? loan.remainingTenureMonths - 1 : 0,
        );
      }
    }

    state = state.copyWith(
      transactions: [newTx, ...state.transactions],
      creditCards: updatedCards,
      loans: updatedLoans,
    );
  }

  void markTransactionSynced(String id) {
    state = state.copyWith(
      transactions: state.transactions.map((t) {
        if (t.id == id) {
          return t.copyWith(syncStatus: SyncStatus.synced);
        }
        return t;
      }).toList(),
    );
  }

  void addAccount({
    required String name,
    required AccountType type,
    String? bank,
    String? accountNumberLast4,
    required double openingBalance,
  }) {
    final newAcc = AccountModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      bank: bank,
      accountNumberLast4: accountNumberLast4,
      openingBalance: openingBalance,
      calculatedBalance: openingBalance,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      accounts: [...state.accounts, newAcc],
    );
  }

  void addCreditCard({
    required String name,
    required String bank,
    required String last4,
    required double creditLimit,
    required int statementDay,
    required int dueDay,
  }) {
    final newCard = CreditCardModel(
      id: _uuid.v4(),
      name: name,
      bank: bank,
      last4: last4,
      creditLimit: creditLimit,
      currentOutstanding: 0.0,
      statementDay: statementDay,
      dueDay: dueDay,
    );

    state = state.copyWith(
      creditCards: [...state.creditCards, newCard],
    );
  }

  void addLoan({
    required String name,
    required String provider,
    required double principalAmount,
    required double interestRate,
    required double monthlyEmi,
    required int dueDay,
    required int tenureMonths,
  }) {
    final newLoan = LoanModel(
      id: _uuid.v4(),
      name: name,
      provider: provider,
      principalAmount: principalAmount,
      outstandingAmount: principalAmount,
      interestRate: interestRate,
      monthlyEmi: monthlyEmi,
      dueDay: dueDay,
      startDate: DateTime.now(),
      remainingTenureMonths: tenureMonths,
    );

    state = state.copyWith(
      loans: [...state.loans, newLoan],
    );
  }

  void addInvestment({
    required String name,
    required InvestmentType type,
    required double investedAmount,
    required double currentValue,
    double monthlySipAmount = 0.0,
    int sipDay = 1,
  }) {
    final newInv = InvestmentModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      investedAmount: investedAmount,
      currentValue: currentValue,
      monthlySipAmount: monthlySipAmount,
      sipDay: sipDay,
    );

    state = state.copyWith(
      investments: [...state.investments, newInv],
    );
  }

  void addGoal({
    required String name,
    required double targetAmount,
    required double currentSavedAmount,
    DateTime? targetDate,
    String icon = 'target',
  }) {
    final newGoal = GoalModel(
      id: _uuid.v4(),
      name: name,
      targetAmount: targetAmount,
      currentSavedAmount: currentSavedAmount,
      targetDate: targetDate,
      icon: icon,
    );

    state = state.copyWith(
      goals: [...state.goals, newGoal],
    );
  }

  void addFundsToGoal(String goalId, double amount) {
    state = state.copyWith(
      goals: state.goals.map((g) {
        if (g.id == goalId) {
          return g.copyWith(currentSavedAmount: g.currentSavedAmount + amount);
        }
        return g;
      }).toList(),
    );
  }

  void deleteGoal(String id) {
    state = state.copyWith(
      goals: state.goals.where((g) => g.id != id).toList(),
    );
  }

  void toggleBiometric(bool value) {
    state = state.copyWith(isBiometricEnabled: value);
  }

  void toggleRoundUp(bool value) {
    state = state.copyWith(isRoundUpEnabled: value);
  }

  void toggleAutoBackup(bool value) {
    state = state.copyWith(isAutoBackupEnabled: value);
  }

  void addCategory({

    required String name,
    required String type,
    required String icon,
    String colorHex = '0xFF6366F1',
    String? parentId,
  }) {
    final newCat = CategoryModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      icon: icon,
      colorHex: colorHex,
      parentId: parentId,
    );

    state = state.copyWith(
      categories: [...state.categories, newCat],
    );
  }

  void deleteCategory(String id) {
    state = state.copyWith(
      categories: state.categories.where((c) => c.id != id).toList(),
    );
  }

  void setEmergencyBuffer(double amount) {
    state = state.copyWith(emergencyBuffer: amount);
  }

  void setCurrencySymbol(String symbol) {
    state = state.copyWith(currencySymbol: symbol);
  }

  void clearForNewUser(String userId) {
    state = _emptyState();
  }

  void deleteTransaction(String id) {



    state = state.copyWith(
      transactions: state.transactions.where((t) => t.id != id).toList(),
    );
  }
}

final financeNotifierProvider = StateNotifierProvider<FinanceNotifier, FinanceState>((ref) {
  return FinanceNotifier();
});
