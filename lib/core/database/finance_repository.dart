import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../../domain/models/models.dart';
import 'app_database.dart';
import 'finance_mappers.dart';

const _uuid = Uuid();

const _kEmergencyBuffer = 'finance_emergency_buffer';
const _kCurrencySymbol = 'finance_currency_symbol';
const _kBiometricEnabled = 'finance_biometric_enabled';
const _kRoundUpEnabled = 'finance_round_up_enabled';
const _kAutoBackupEnabled = 'finance_auto_backup_enabled';

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

  /// Total Liquid Money across active accounts holding readily spendable cash.
  /// Includes savings/current/bank/cash/wallet balances; excludes locked-in
  /// instruments (FD/RD/investment accounts) which are counted under investments.
  double get totalLiquidBalance {
    const liquidTypes = {
      AccountType.bankAccount,
      AccountType.savingsAccount,
      AccountType.currentAccount,
      AccountType.cash,
      AccountType.wallet,
    };
    return accountsWithCalculatedBalances
        .where((a) => a.isActive && liquidTypes.contains(a.type))
        .fold(0.0, (sum, a) => sum + a.calculatedBalance);
  }

  /// Liquid balance as of the end of each of the last [months] months
  /// (oldest first), replayed from real transaction history. There is no
  /// historical snapshot of investments/loans, so this can't be a true net
  /// worth trend — it's presented on the Net Worth screen as a liquid-cash
  /// trend, which is the honest thing the data actually supports.
  List<double> liquidBalanceTrend({int months = 6}) {
    const liquidTypes = {
      AccountType.bankAccount,
      AccountType.savingsAccount,
      AccountType.currentAccount,
      AccountType.cash,
      AccountType.wallet,
    };
    final liquidAccounts = accounts.where((a) => a.isActive && liquidTypes.contains(a.type)).toList();
    final now = DateTime.now();

    return List.generate(months, (i) {
      final monthsAgo = months - 1 - i;
      final monthEnd = DateTime(now.year, now.month - monthsAgo + 1, 0, 23, 59, 59);
      double total = 0;
      for (final acc in liquidAccounts) {
        double calc = acc.openingBalance;
        for (final tx in transactions) {
          if (tx.date.isAfter(monthEnd)) continue;
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
          if (tx.toAccountId == acc.id) {
            calc += tx.amount;
          }
        }
        total += calc;
      }
      return total;
    });
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

  /// Budgets with `spentAmount` recomputed live from actual expense
  /// transactions in that budget's category and month. The stored
  /// `spentAmount` field is not authoritative — this getter is, exactly like
  /// [accountsWithCalculatedBalances] is for account balances.
  List<BudgetModel> get budgetsWithCalculatedSpend {
    return budgets.map((b) {
      final spent = transactions
          .where((t) =>
              t.categoryId == b.categoryId &&
              t.type == TransactionType.expense &&
              '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}' == b.monthYear)
          .fold(0.0, (sum, t) => sum + t.amount);
      return BudgetModel(
        id: b.id,
        categoryId: b.categoryId,
        monthlyLimit: b.monthlyLimit,
        monthYear: b.monthYear,
        spentAmount: spent,
      );
    }).toList();
  }

  /// Upcoming Payments total for the next 30 days
  double get upcomingPaymentsTotal {
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 30));
    return recurringPayments
        .where((p) => !p.nextDueDate.isBefore(now) && p.nextDueDate.isBefore(cutoff))
        .fold(0.0, (sum, p) => sum + p.amount);
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
  final AppDatabase _db;

  /// [autoLoad] is disabled in unit tests so state stays purely in-memory and
  /// synchronous, without racing an async DB read against the test body.
  FinanceNotifier(this._db, {bool autoLoad = true}) : super(_emptyState()) {
    if (autoLoad) {
      _loadPersistedState();
    }
  }

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

  /// Clean empty state — used before persisted data has loaded
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

  /// Re-reads everything from disk and replaces in-memory state. Used after
  /// a vault restore writes directly to the database, so the UI reflects the
  /// restored data without requiring an app restart.
  Future<void> reloadFromDb() => _loadPersistedState();

  /// Loads all persisted finance data (SQLite via Drift) and app-level
  /// settings (SharedPreferences) at startup so nothing is lost on restart.
  Future<void> _loadPersistedState() async {
    try {
      final accounts = (await _db.select(_db.accounts).get()).map((e) => e.toModel()).toList();
      var categories = (await _db.select(_db.categories).get()).map((e) => e.toModel()).toList();
      final transactions = (await _db.select(_db.transactions).get()).map((e) => e.toModel()).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final creditCards = (await _db.select(_db.creditCards).get()).map((e) => e.toModel()).toList();
      final loans = (await _db.select(_db.loans).get()).map((e) => e.toModel()).toList();
      final budgets = (await _db.select(_db.budgets).get()).map((e) => e.toModel()).toList();
      final recurringPayments = (await _db.select(_db.recurringPayments).get()).map((e) => e.toModel()).toList();
      final investments = (await _db.select(_db.investments).get()).map((e) => e.toModel()).toList();
      final goals = (await _db.select(_db.goals).get()).map((e) => e.toModel()).toList();

      if (categories.isEmpty) {
        categories = _defaultCategories();
        for (final cat in categories) {
          await _db.into(_db.categories).insertOnConflictUpdate(cat.toCompanion());
        }
      }

      final prefs = await SharedPreferences.getInstance();

      state = FinanceState(
        accounts: accounts,
        categories: categories,
        transactions: transactions,
        creditCards: creditCards,
        loans: loans,
        budgets: budgets,
        recurringPayments: recurringPayments,
        investments: investments,
        goals: goals,
        emergencyBuffer: prefs.getDouble(_kEmergencyBuffer) ?? 20000.0,
        currencySymbol: prefs.getString(_kCurrencySymbol) ?? '₹',
        isBiometricEnabled: prefs.getBool(_kBiometricEnabled) ?? false,
        isRoundUpEnabled: prefs.getBool(_kRoundUpEnabled) ?? false,
        isAutoBackupEnabled: prefs.getBool(_kAutoBackupEnabled) ?? false,
      );
    } catch (e, st) {
      debugPrint('FinanceNotifier: failed to load persisted data: $e\n$st');
    }
  }

  void _fireAndForget(Future<void> Function() op, String label) {
    op().catchError((Object e, StackTrace st) {
      debugPrint('FinanceNotifier: failed to persist $label: $e');
    });
  }

  Future<void> _savePref(Future<void> Function(SharedPreferences prefs) op) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await op(prefs);
    } catch (e) {
      debugPrint('FinanceNotifier: failed to persist setting: $e');
    }
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
          // Payment reduces outstanding; can't go below zero (overpayment).
          newOutstanding = (card.currentOutstanding - amount).clamp(0.0, double.infinity);
        } else if (type == TransactionType.expense) {
          // Spending charges to card increases outstanding. Not capped at
          // creditLimit — real cards can go over-limit; silently discarding
          // the excess would understate actual debt owed.
          newOutstanding = card.currentOutstanding + amount;
        }

        updatedCards[cardIdx] = card.copyWith(currentOutstanding: newOutstanding);
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

    _fireAndForget(() => _db.into(_db.transactions).insertOnConflictUpdate(newTx.toCompanion()), 'transaction');

    if (creditCardId != null) {
      final idx = updatedCards.indexWhere((c) => c.id == creditCardId);
      if (idx != -1) {
        _fireAndForget(() => _db.into(_db.creditCards).insertOnConflictUpdate(updatedCards[idx].toCompanion()), 'credit card outstanding');
      }
    }
    if (type == TransactionType.loanPayment && loanId != null) {
      final idx = updatedLoans.indexWhere((l) => l.id == loanId);
      if (idx != -1) {
        _fireAndForget(() => _db.into(_db.loans).insertOnConflictUpdate(updatedLoans[idx].toCompanion()), 'loan outstanding');
      }
    }
  }

  void markTransactionSynced(String id) {
    TransactionModel? updated;
    state = state.copyWith(
      transactions: state.transactions.map((t) {
        if (t.id == id) {
          updated = t.copyWith(syncStatus: SyncStatus.synced);
          return updated!;
        }
        return t;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.transactions).insertOnConflictUpdate(updated!.toCompanion()), 'transaction sync status');
    }
  }

  /// Edits an existing transaction's descriptive fields and amount.
  ///
  /// Deliberately does NOT allow changing `type`/`accountId`/`toAccountId`/
  /// `creditCardId`/`loanId` — those determine how the transaction affected
  /// account balances and card/loan outstanding at creation time, and
  /// re-deriving that correctly for an arbitrary type change is exactly the
  /// kind of "just delete and recreate it" situation most finance apps push
  /// users toward, rather than risk silently corrupting a balance. Editing
  /// `amount` is supported and correctly adjusts the linked card/loan
  /// outstanding by the delta.
  void updateTransaction(String id, {
    double? amount,
    String? categoryId,
    String? merchant,
    DateTime? date,
    String? description,
    String? notes,
    List<String>? tags,
  }) {
    final original = state.transactions.firstWhere((t) => t.id == id);
    final newAmount = amount ?? original.amount;
    final delta = newAmount - original.amount;

    final updated = original.copyWith(
      amount: newAmount,
      categoryId: categoryId ?? original.categoryId,
      merchant: merchant ?? original.merchant,
      date: date ?? original.date,
      description: description ?? original.description,
      notes: notes ?? original.notes,
      tags: tags ?? original.tags,
    );

    List<CreditCardModel> updatedCards = state.creditCards;
    List<LoanModel> updatedLoans = state.loans;
    CreditCardModel? adjustedCard;
    LoanModel? adjustedLoan;

    if (delta != 0 && original.creditCardId != null) {
      final cardIdx = state.creditCards.indexWhere((c) => c.id == original.creditCardId);
      if (cardIdx != -1) {
        final card = state.creditCards[cardIdx];
        final sign = original.type == TransactionType.creditCardPayment ? -1 : 1;
        final newOutstanding = (card.currentOutstanding + (delta * sign)).clamp(0.0, double.infinity);
        adjustedCard = card.copyWith(currentOutstanding: newOutstanding);
        updatedCards = List.from(state.creditCards)..[cardIdx] = adjustedCard;
      }
    }

    if (delta != 0 && original.type == TransactionType.loanPayment && original.loanId != null) {
      final loanIdx = state.loans.indexWhere((l) => l.id == original.loanId);
      if (loanIdx != -1) {
        final loan = state.loans[loanIdx];
        final newOutstanding = (loan.outstandingAmount - delta).clamp(0.0, loan.principalAmount);
        adjustedLoan = LoanModel(
          id: loan.id, name: loan.name, provider: loan.provider,
          principalAmount: loan.principalAmount, outstandingAmount: newOutstanding,
          interestRate: loan.interestRate, monthlyEmi: loan.monthlyEmi, dueDay: loan.dueDay,
          startDate: loan.startDate, remainingTenureMonths: loan.remainingTenureMonths,
        );
        updatedLoans = List.from(state.loans)..[loanIdx] = adjustedLoan;
      }
    }

    state = state.copyWith(
      transactions: state.transactions.map((t) => t.id == id ? updated : t).toList(),
      creditCards: updatedCards,
      loans: updatedLoans,
    );

    _fireAndForget(() => _db.into(_db.transactions).insertOnConflictUpdate(updated.toCompanion()), 'transaction update');
    if (adjustedCard != null) {
      _fireAndForget(() => _db.into(_db.creditCards).insertOnConflictUpdate(adjustedCard!.toCompanion()), 'credit card outstanding after edit');
    }
    if (adjustedLoan != null) {
      _fireAndForget(() => _db.into(_db.loans).insertOnConflictUpdate(adjustedLoan!.toCompanion()), 'loan outstanding after edit');
    }
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

    _fireAndForget(() => _db.into(_db.accounts).insertOnConflictUpdate(newAcc.toCompanion()), 'account');
  }

  void addCard({
    required CardType cardType,
    required String name,
    required String bank,
    required String last4,
    required String cardholderName,
    CardNetwork network = CardNetwork.visa,
    int? expiryMonth,
    int? expiryYear,
    CardColorPreset colorPreset = CardColorPreset.midnight,
    bool isVirtual = false,
    String? notes,
    // Credit-card fields
    double creditLimit = 0,
    int statementDay = 1,
    int dueDay = 15,
    String? linkedAccountId,
    // Prepaid / forex fields
    double? balance,
    String? currency,
  }) {
    final newCard = CardModel(
      id: _uuid.v4(),
      cardType: cardType,
      name: name,
      bank: bank,
      last4: last4,
      cardholderName: cardholderName,
      network: network,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      colorPreset: colorPreset,
      isVirtual: isVirtual,
      notes: notes,
      creditLimit: creditLimit,
      currentOutstanding: 0.0,
      statementDay: statementDay,
      dueDay: dueDay,
      linkedAccountId: linkedAccountId,
      balance: balance,
      currency: currency,
    );
    state = state.copyWith(
      creditCards: [...state.creditCards, newCard],
    );

    _fireAndForget(() => _db.into(_db.creditCards).insertOnConflictUpdate(newCard.toCompanion()), 'credit card');
  }

  /// Backward-compat wrapper so existing calls compile
  void addCreditCard({
    required String name,
    required String bank,
    required String last4,
    required double creditLimit,
    required int statementDay,
    required int dueDay,
    String cardholderName = '',
  }) {
    addCard(
      cardType: CardType.credit,
      name: name,
      bank: bank,
      last4: last4,
      cardholderName: cardholderName,
      creditLimit: creditLimit,
      statementDay: statementDay,
      dueDay: dueDay,
    );
  }

  void updateCard(String cardId, {
    String? name,
    String? bank,
    String? last4,
    String? cardholderName,
    CardNetwork? network,
    int? expiryMonth,
    int? expiryYear,
    CardColorPreset? colorPreset,
    String? notes,
    double? creditLimit,
    int? statementDay,
    int? dueDay,
    String? linkedAccountId,
    double? balance,
    String? currency,
  }) {
    CardModel? updated;
    state = state.copyWith(
      creditCards: state.creditCards.map((c) {
        if (c.id != cardId) return c;
        updated = c.copyWith(
          name: name,
          bank: bank,
          last4: last4,
          cardholderName: cardholderName,
          network: network,
          expiryMonth: expiryMonth,
          expiryYear: expiryYear,
          colorPreset: colorPreset,
          notes: notes,
          creditLimit: creditLimit,
          statementDay: statementDay,
          dueDay: dueDay,
          linkedAccountId: linkedAccountId,
          balance: balance,
          currency: currency,
        );
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.creditCards).insertOnConflictUpdate(updated!.toCompanion()), 'card update');
    }
  }

  void deleteCard(String cardId) {
    state = state.copyWith(
      creditCards: state.creditCards.where((c) => c.id != cardId).toList(),
    );
    _fireAndForget(() => (_db.delete(_db.creditCards)..where((c) => c.id.equals(cardId))).go(), 'credit card deletion');
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

    _fireAndForget(() => _db.into(_db.loans).insertOnConflictUpdate(newLoan.toCompanion()), 'loan');
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

    _fireAndForget(() => _db.into(_db.investments).insertOnConflictUpdate(newInv.toCompanion()), 'investment');
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

    _fireAndForget(() => _db.into(_db.goals).insertOnConflictUpdate(newGoal.toCompanion()), 'goal');
  }

  void addFundsToGoal(String goalId, double amount) {
    GoalModel? updated;
    state = state.copyWith(
      goals: state.goals.map((g) {
        if (g.id == goalId) {
          updated = g.copyWith(currentSavedAmount: g.currentSavedAmount + amount);
          return updated!;
        }
        return g;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.goals).insertOnConflictUpdate(updated!.toCompanion()), 'goal funds');
    }
  }

  void deleteGoal(String id) {
    state = state.copyWith(
      goals: state.goals.where((g) => g.id != id).toList(),
    );
    _fireAndForget(() => (_db.delete(_db.goals)..where((g) => g.id.equals(id))).go(), 'goal deletion');
  }

  void toggleBiometric(bool value) {
    state = state.copyWith(isBiometricEnabled: value);
    _savePref((prefs) => prefs.setBool(_kBiometricEnabled, value));
  }

  void toggleRoundUp(bool value) {
    state = state.copyWith(isRoundUpEnabled: value);
    _savePref((prefs) => prefs.setBool(_kRoundUpEnabled, value));
  }

  void toggleAutoBackup(bool value) {
    state = state.copyWith(isAutoBackupEnabled: value);
    _savePref((prefs) => prefs.setBool(_kAutoBackupEnabled, value));
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

    _fireAndForget(() => _db.into(_db.categories).insertOnConflictUpdate(newCat.toCompanion()), 'category');
  }

  void deleteCategory(String id) {
    state = state.copyWith(
      categories: state.categories.where((c) => c.id != id).toList(),
    );
    _fireAndForget(() => (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go(), 'category deletion');
  }

  void setEmergencyBuffer(double amount) {
    state = state.copyWith(emergencyBuffer: amount);
    _savePref((prefs) => prefs.setDouble(_kEmergencyBuffer, amount));
  }

  void setCurrencySymbol(String symbol) {
    state = state.copyWith(currencySymbol: symbol);
    _savePref((prefs) => prefs.setString(_kCurrencySymbol, symbol));
  }

  /// Wipes all locally persisted finance data and resets to a clean slate —
  /// used when switching to a different signed-in user on the same device.
  void clearForNewUser(String userId) {
    state = _emptyState();
    _fireAndForget(() async {
      await _db.wipeAllData();
      for (final cat in _defaultCategories()) {
        await _db.into(_db.categories).insertOnConflictUpdate(cat.toCompanion());
      }
    }, 'clearing data for new user');
  }

  void deleteTransaction(String id) {
    state = state.copyWith(
      transactions: state.transactions.where((t) => t.id != id).toList(),
    );
    _fireAndForget(() => (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go(), 'transaction deletion');
  }

  // ── Accounts ───────────────────────────────────────────────────────────────
  void deleteAccount(String id) {
    state = state.copyWith(
      accounts: state.accounts.where((a) => a.id != id).toList(),
    );
    _fireAndForget(() => (_db.delete(_db.accounts)..where((a) => a.id.equals(id))).go(), 'account deletion');
  }

  void updateAccount(String id, {String? name, AccountType? type, String? bank, String? accountNumberLast4, double? openingBalance}) {
    AccountModel? updated;
    state = state.copyWith(
      accounts: state.accounts.map((a) {
        if (a.id != id) return a;
        updated = a.copyWith(name: name, type: type, bank: bank, accountNumberLast4: accountNumberLast4, openingBalance: openingBalance);
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.accounts).insertOnConflictUpdate(updated!.toCompanion()), 'account update');
    }
  }

  // ── Loans ──────────────────────────────────────────────────────────────────
  void deleteLoan(String id) {
    state = state.copyWith(loans: state.loans.where((l) => l.id != id).toList());
    _fireAndForget(() => (_db.delete(_db.loans)..where((l) => l.id.equals(id))).go(), 'loan deletion');
  }

  void updateLoan(String id, {String? name, String? provider, double? outstandingAmount, double? monthlyEmi, int? dueDay}) {
    LoanModel? updated;
    state = state.copyWith(
      loans: state.loans.map((l) {
        if (l.id != id) return l;
        updated = LoanModel(
          id: l.id,
          name: name ?? l.name,
          provider: provider ?? l.provider,
          principalAmount: l.principalAmount,
          outstandingAmount: outstandingAmount ?? l.outstandingAmount,
          interestRate: l.interestRate,
          monthlyEmi: monthlyEmi ?? l.monthlyEmi,
          dueDay: dueDay ?? l.dueDay,
          startDate: l.startDate,
          remainingTenureMonths: l.remainingTenureMonths,
        );
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.loans).insertOnConflictUpdate(updated!.toCompanion()), 'loan update');
    }
  }

  // ── Budgets ────────────────────────────────────────────────────────────────
  void addBudget({required String categoryId, required double monthlyLimit, String? monthYear}) {
    final now = DateTime.now();
    final resolvedMonthYear = monthYear ?? '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final newBudget = BudgetModel(
      id: _uuid.v4(),
      categoryId: categoryId,
      monthlyLimit: monthlyLimit,
      monthYear: resolvedMonthYear,
      spentAmount: 0.0,
    );
    state = state.copyWith(budgets: [...state.budgets, newBudget]);
    _fireAndForget(() => _db.into(_db.budgets).insertOnConflictUpdate(newBudget.toCompanion()), 'budget');
  }

  void deleteBudget(String id) {
    state = state.copyWith(budgets: state.budgets.where((b) => b.id != id).toList());
    _fireAndForget(() => (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go(), 'budget deletion');
  }

  void updateBudget(String id, {double? limitAmount, String? categoryId}) {
    BudgetModel? updated;
    state = state.copyWith(
      budgets: state.budgets.map((b) {
        if (b.id != id) return b;
        updated = BudgetModel(
          id: b.id,
          categoryId: categoryId ?? b.categoryId,
          monthlyLimit: limitAmount ?? b.monthlyLimit,
          monthYear: b.monthYear,
          spentAmount: b.spentAmount,
        );
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.budgets).insertOnConflictUpdate(updated!.toCompanion()), 'budget update');
    }
  }

  // ── Recurring Payments ───────────────────────────────────────────────────────
  void addRecurringPayment({
    required String title,
    required double amount,
    required PaymentFrequency frequency,
    required DateTime nextDueDate,
    String? categoryId,
    String? accountId,
    bool isAutoPay = false,
  }) {
    final newPayment = RecurringPaymentModel(
      id: _uuid.v4(),
      title: title,
      amount: amount,
      frequency: frequency,
      nextDueDate: nextDueDate,
      categoryId: categoryId,
      accountId: accountId,
      isAutoPay: isAutoPay,
    );
    state = state.copyWith(recurringPayments: [...state.recurringPayments, newPayment]);
    _fireAndForget(() => _db.into(_db.recurringPayments).insertOnConflictUpdate(newPayment.toCompanion()), 'recurring payment');
  }

  void updateRecurringPayment(String id, {
    String? title,
    double? amount,
    PaymentFrequency? frequency,
    DateTime? nextDueDate,
    String? categoryId,
    String? accountId,
    bool? isAutoPay,
  }) {
    RecurringPaymentModel? updated;
    state = state.copyWith(
      recurringPayments: state.recurringPayments.map((p) {
        if (p.id != id) return p;
        updated = RecurringPaymentModel(
          id: p.id,
          title: title ?? p.title,
          amount: amount ?? p.amount,
          frequency: frequency ?? p.frequency,
          nextDueDate: nextDueDate ?? p.nextDueDate,
          categoryId: categoryId ?? p.categoryId,
          accountId: accountId ?? p.accountId,
          isAutoPay: isAutoPay ?? p.isAutoPay,
        );
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.recurringPayments).insertOnConflictUpdate(updated!.toCompanion()), 'recurring payment update');
    }
  }

  void deleteRecurringPayment(String id) {
    state = state.copyWith(recurringPayments: state.recurringPayments.where((p) => p.id != id).toList());
    _fireAndForget(() => (_db.delete(_db.recurringPayments)..where((p) => p.id.equals(id))).go(), 'recurring payment deletion');
  }

  // ── Investments ────────────────────────────────────────────────────────────
  void deleteInvestment(String id) {
    state = state.copyWith(investments: state.investments.where((i) => i.id != id).toList());
    _fireAndForget(() => (_db.delete(_db.investments)..where((i) => i.id.equals(id))).go(), 'investment deletion');
  }

  void updateInvestment(String id, {String? name, double? currentValue, double? investedAmount, double? monthlySipAmount}) {
    InvestmentModel? updated;
    state = state.copyWith(
      investments: state.investments.map((inv) {
        if (inv.id != id) return inv;
        updated = InvestmentModel(
          id: inv.id,
          name: name ?? inv.name,
          type: inv.type,
          investedAmount: investedAmount ?? inv.investedAmount,
          currentValue: currentValue ?? inv.currentValue,
          monthlySipAmount: monthlySipAmount ?? inv.monthlySipAmount,
          sipDay: inv.sipDay,
        );
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.investments).insertOnConflictUpdate(updated!.toCompanion()), 'investment update');
    }
  }

  // ── Goals (update) ─────────────────────────────────────────────────────────
  void updateGoal(String id, {String? name, double? targetAmount, DateTime? targetDate}) {
    GoalModel? updated;
    state = state.copyWith(
      goals: state.goals.map((g) {
        if (g.id != id) return g;
        updated = g.copyWith(name: name, targetAmount: targetAmount, targetDate: targetDate);
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.goals).insertOnConflictUpdate(updated!.toCompanion()), 'goal update');
    }
  }

  // ── Categories (update) ───────────────────────────────────────────────────
  void updateCategory(String id, {String? name, String? icon, String? colorHex}) {
    CategoryModel? updated;
    state = state.copyWith(
      categories: state.categories.map((c) {
        if (c.id != id) return c;
        updated = CategoryModel(
          id: c.id, name: name ?? c.name, type: c.type,
          icon: icon ?? c.icon, colorHex: colorHex ?? c.colorHex, parentId: c.parentId,
        );
        return updated!;
      }).toList(),
    );
    if (updated != null) {
      _fireAndForget(() => _db.into(_db.categories).insertOnConflictUpdate(updated!.toCompanion()), 'category update');
    }
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final financeNotifierProvider = StateNotifierProvider<FinanceNotifier, FinanceState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return FinanceNotifier(db);
});
