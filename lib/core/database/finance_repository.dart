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

  FinanceState({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.creditCards,
    required this.loans,
    required this.budgets,
    required this.recurringPayments,
  });

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

  /// Total Liabilities = Credit Cards + Loans
  double get totalLiabilities => totalCreditCardDebt + totalLoanDebt;

  /// Total Assets = Liquid Money + Investments / FDs
  double get totalAssets {
    double liquid = totalLiquidBalance;
    double investments = accountsWithCalculatedBalances
        .where((a) => a.type == AccountType.fd || a.type == AccountType.rd || a.type == AccountType.investmentAccount || a.type == AccountType.otherAsset)
        .fold(0.0, (sum, a) => sum + a.calculatedBalance);
    return liquid + investments + 750000.0; // Mock SIP/Stocks portfolio value
  }

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

  /// Safe To Spend = Liquid Balance - Upcoming Obligations - Minimum Buffer (₹20,000)
  double get safeToSpend {
    const double emergencyBuffer = 20000.0;
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
  }) {
    return FinanceState(
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      creditCards: creditCards ?? this.creditCards,
      loans: loans ?? this.loans,
      budgets: budgets ?? this.budgets,
      recurringPayments: recurringPayments ?? this.recurringPayments,
    );
  }
}

class FinanceNotifier extends StateNotifier<FinanceState> {
  FinanceNotifier() : super(_initialSeedState());

  static FinanceState _initialSeedState() {
    final now = DateTime.now();

    final categories = [
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

    final accounts = [
      AccountModel(
        id: 'acc_hdfc',
        name: 'HDFC Savings Account',
        type: AccountType.savingsAccount,
        bank: 'HDFC Bank',
        accountNumberLast4: '5421',
        openingBalance: 52430.0,
        calculatedBalance: 52430.0,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
      AccountModel(
        id: 'acc_sbi',
        name: 'SBI Savings Account',
        type: AccountType.savingsAccount,
        bank: 'State Bank of India',
        accountNumberLast4: '8812',
        openingBalance: 21820.0,
        calculatedBalance: 21820.0,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
      AccountModel(
        id: 'acc_icici',
        name: 'ICICI Savings',
        type: AccountType.savingsAccount,
        bank: 'ICICI Bank',
        accountNumberLast4: '3341',
        openingBalance: 18200.0,
        calculatedBalance: 18200.0,
        createdAt: now.subtract(const Duration(days: 60)),
      ),
      AccountModel(
        id: 'acc_cash',
        name: 'Cash Wallet',
        type: AccountType.cash,
        openingBalance: 4500.0,
        calculatedBalance: 4500.0,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
    ];

    final creditCards = [
      CreditCardModel(
        id: 'card_sbi',
        name: 'SBI Cashback Card',
        bank: 'SBI Card',
        last4: '4321',
        creditLimit: 200000.0,
        currentOutstanding: 47700.0,
        statementDay: 2,
        dueDay: 22,
        linkedAccountId: 'acc_sbi',
      ),
      CreditCardModel(
        id: 'card_hdfc',
        name: 'HDFC Regalia',
        bank: 'HDFC Bank',
        last4: '9981',
        creditLimit: 150000.0,
        currentOutstanding: 31200.0,
        statementDay: 5,
        dueDay: 25,
        linkedAccountId: 'acc_hdfc',
      ),
    ];

    final loans = [
      LoanModel(
        id: 'loan_home',
        name: 'Home Loan',
        provider: 'SBI Home Loans',
        principalAmount: 3500000.0,
        outstandingAmount: 2842000.0,
        interestRate: 8.5,
        monthlyEmi: 30000.0,
        dueDay: 28,
        startDate: DateTime(2023, 1, 15),
        remainingTenureMonths: 168,
      ),
    ];

    final transactions = [
      TransactionModel(
        id: 'tx_1',
        accountId: 'acc_hdfc',
        type: TransactionType.income,
        amount: 86250.0,
        categoryId: 'cat_salary',
        merchant: 'TechCorp Pvt Ltd',
        date: DateTime(now.year, now.month, 1),
        description: 'August Salary',
        createdAt: DateTime(now.year, now.month, 1),
      ),
      TransactionModel(
        id: 'tx_2',
        accountId: 'acc_hdfc',
        type: TransactionType.expense,
        amount: 2450.0,
        categoryId: 'cat_shopping',
        merchant: 'Amazon',
        date: now.subtract(const Duration(days: 2)),
        description: 'Electronics accessory',
        tags: ['Shopping', 'Tech'],
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      TransactionModel(
        id: 'tx_3',
        accountId: 'acc_hdfc',
        type: TransactionType.expense,
        amount: 780.0,
        categoryId: 'cat_food',
        merchant: 'Swiggy',
        date: now.subtract(const Duration(days: 1)),
        description: 'Dinner order',
        tags: ['Food'],
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      TransactionModel(
        id: 'tx_4',
        accountId: 'acc_sbi',
        type: TransactionType.expense,
        amount: 3000.0,
        categoryId: 'cat_transport',
        merchant: 'Shell Fuel Station',
        date: now.subtract(const Duration(days: 3)),
        description: 'Petrol fill',
        tags: ['Fuel'],
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ];

    final budgets = [
      BudgetModel(id: 'b_1', categoryId: 'cat_food', monthlyLimit: 10000.0, monthYear: '${now.year}-${now.month.toString().padLeft(2, '0')}', spentAmount: 8000.0),
      BudgetModel(id: 'b_2', categoryId: 'cat_shopping', monthlyLimit: 5000.0, monthYear: '${now.year}-${now.month.toString().padLeft(2, '0')}', spentAmount: 4500.0),
      BudgetModel(id: 'b_3', categoryId: 'cat_transport', monthlyLimit: 4000.0, monthYear: '${now.year}-${now.month.toString().padLeft(2, '0')}', spentAmount: 2800.0),
    ];

    final recurringPayments = [
      RecurringPaymentModel(id: 'rec_1', title: 'SBI Card Bill', amount: 12450.0, frequency: PaymentFrequency.monthly, nextDueDate: DateTime(now.year, now.month, 25), categoryId: 'cat_bills', accountId: 'acc_sbi'),
      RecurringPaymentModel(id: 'rec_2', title: 'Home Loan EMI', amount: 30000.0, frequency: PaymentFrequency.monthly, nextDueDate: DateTime(now.year, now.month, 28), categoryId: 'cat_housing', accountId: 'acc_hdfc'),
      RecurringPaymentModel(id: 'rec_3', title: 'Mutual Fund SIP', amount: 8000.0, frequency: PaymentFrequency.monthly, nextDueDate: DateTime(now.year, now.month + 1, 1), categoryId: 'cat_investment', accountId: 'acc_hdfc'),
    ];

    return FinanceState(
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      creditCards: creditCards,
      loans: loans,
      budgets: budgets,
      recurringPayments: recurringPayments,
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
      createdAt: DateTime.now(),
    );

    // If credit card payment transfer
    List<CreditCardModel> updatedCards = List.from(state.creditCards);
    if (type == TransactionType.creditCardPayment && creditCardId != null) {
      final cardIdx = updatedCards.indexWhere((c) => c.id == creditCardId);
      if (cardIdx != -1) {
        final card = updatedCards[cardIdx];
        final newOutstanding = (card.currentOutstanding - amount).clamp(0.0, card.creditLimit);
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

  void deleteTransaction(String id) {
    state = state.copyWith(
      transactions: state.transactions.where((t) => t.id != id).toList(),
    );
  }
}

final financeNotifierProvider = StateNotifierProvider<FinanceNotifier, FinanceState>((ref) {
  return FinanceNotifier();
});
