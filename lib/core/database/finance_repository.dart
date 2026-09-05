import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../utils/currency_formatter.dart';
import '../services/supabase_service.dart';
import '../sync/cloud_mappers.dart';
import '../sync/cloud_direct_write.dart';
import '../services/secret_cipher_service.dart';
import '../services/notification_service.dart';
import '../services/payment_reminders.dart';
import '../../domain/models/models.dart';
import 'app_database.dart';
import 'finance_mappers.dart';

const _uuid = Uuid();

const _kEmergencyBuffer = kPrefEmergencyBuffer;
const _kCurrencySymbol = kPrefCurrencySymbol;
const _kBiometricEnabled = kPrefBiometricEnabled;
const _kRoundUpEnabled = kPrefRoundUpEnabled;
const _kAutoBackupEnabled = kPrefAutoBackupEnabled;

/// The finance entity tables synced with the cloud (`notes` is handled by
/// `NotesNotifier` instead). Order mirrors the old sync engine's push/pull
/// order: parents before children.
const List<String> _financeCloudTables = <String>[
  'accounts',
  'categories',
  'transactions',
  'credit_cards',
  'loans',
  'budgets',
  'recurring_payments',
  'investments',
  'goals',
  'companies',
];

/// Page size for [FinanceNotifier.refreshFromCloud]'s paginated fetch —
/// matches the page size the old sync engine's `SupabaseCloudGateway.pull`
/// used.
const int _kRefreshPageSize = 500;

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
  final List<CompanyModel> companies;
  final double emergencyBuffer;
  final String currencySymbol;
  final bool isBiometricEnabled;
  final bool isRoundUpEnabled;
  final bool isAutoBackupEnabled;

  /// True while [FinanceNotifier.refreshFromCloud] is in flight. Drives the
  /// "Refresh now" spinner in Settings.
  final bool isRefreshing;

  /// When the last successful full refresh from the cloud completed. Null
  /// until the first one finishes (or on a device that has never had a cloud
  /// session, e.g. a demo account).
  final DateTime? lastRefreshedAt;

  /// Set when the last [FinanceNotifier.refreshFromCloud] attempt failed —
  /// cleared on the next successful one. The local cache is left exactly as
  /// it was, so this is surfaced as a subtle indicator, not a blocking error.
  final String? lastRefreshError;

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
    this.companies = const [],
    this.emergencyBuffer = 20000.0,
    this.currencySymbol = '₹',
    this.isBiometricEnabled = false,
    this.isRoundUpEnabled = false,
    this.isAutoBackupEnabled = false,
    this.isRefreshing = false,
    this.lastRefreshedAt,
    this.lastRefreshError,
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

  /// PF balance is just an EPF-typed Investment row's currentValue — already
  /// folded into totalInvestmentCurrentValue/totalAssets automatically. This
  /// getter exists purely so a PF-specific UI tile doesn't need its own filter.
  double get totalProvidentFundValue {
    return investments.where((i) => i.type == InvestmentType.epf).fold(0.0, (sum, i) => sum + i.currentValue);
  }

  /// Returns all descendant category IDs (including self) for a given category ID.
  /// Used for budget rollup: if budget is on parent category, include child category spending.
  List<String> _getCategoryAndDescendants(String categoryId) {
    final result = <String>{categoryId};
    final children = categories.where((c) => c.parentId == categoryId).map((c) => c.id).toList();
    for (final child in children) {
      result.addAll(_getCategoryAndDescendants(child));
    }
    return result.toList();
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
    // A credit-card charge/refund needs *some* real `accountId` (the cloud
    // schema's FK requires one), but that account is just a reference — the
    // actual money movement is the card's own `currentOutstanding` (mutated
    // in add/update/deleteTransaction). Skip those rows here so the
    // reference account isn't double-counted.
    final creditCardIds = {for (final c in creditCards) if (c.cardType == CardType.credit) c.id};
    return accounts.map((acc) {
      double calc = acc.openingBalance;

      for (var tx in transactions) {
        if (tx.accountId == acc.id) {
          final isCardCharge = tx.creditCardId != null &&
              creditCardIds.contains(tx.creditCardId) &&
              (tx.type == TransactionType.expense || tx.type == TransactionType.refund);
          // A salary-linked PF contribution (isExternalToAccount): the money
          // was diverted by the employer before it ever reached this account,
          // so it must not be debited here either — see logSalary.
          if (!isCardCharge && !tx.isExternalToAccount) {
            if (tx.type == TransactionType.income || tx.type == TransactionType.refund) {
              calc += tx.amount;
            } else if (tx.type == TransactionType.expense ||
                tx.type == TransactionType.transfer ||
                tx.type == TransactionType.creditCardPayment ||
                tx.type == TransactionType.loanPayment ||
                tx.type == TransactionType.investment ||
                tx.type == TransactionType.adjustment) {
              calc -= tx.amount;
            }
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
    // See accountsWithCalculatedBalances: a credit-card charge/refund's
    // `accountId` is just an FK reference, not real money movement.
    final creditCardIds = {for (final c in creditCards) if (c.cardType == CardType.credit) c.id};

    return List.generate(months, (i) {
      final monthsAgo = months - 1 - i;
      final monthEnd = DateTime(now.year, now.month - monthsAgo + 1, 0, 23, 59, 59);
      double total = 0;
      for (final acc in liquidAccounts) {
        double calc = acc.openingBalance;
        for (final tx in transactions) {
          if (tx.date.isAfter(monthEnd)) continue;
          final isCardCharge = tx.creditCardId != null &&
              creditCardIds.contains(tx.creditCardId) &&
              (tx.type == TransactionType.expense || tx.type == TransactionType.refund);
          if (tx.accountId == acc.id && !isCardCharge && !tx.isExternalToAccount) {
            if (tx.type == TransactionType.income || tx.type == TransactionType.refund) {
              calc += tx.amount;
            } else if (tx.type == TransactionType.expense ||
                tx.type == TransactionType.transfer ||
                tx.type == TransactionType.creditCardPayment ||
                tx.type == TransactionType.loanPayment ||
                tx.type == TransactionType.investment ||
                tx.type == TransactionType.adjustment) {
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


  /// Monthly Income (Current Month) - uses local time for consistency with transaction dates
  double get monthlyIncome {
    final now = DateTime.now();
    return transactions
        .where((t) => (t.type == TransactionType.income || t.type == TransactionType.refund) && t.date.month == now.month && t.date.year == now.year)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Net salary/other income logged this month, grouped by company. Only
  /// `income`-type transactions count (a linked PF-contribution leg is
  /// `TransactionType.investment`, already excluded here — see logSalary).
  Map<String, double> monthlyIncomeByCompany({DateTime? month}) {
    final m = month ?? DateTime.now();
    return {
      for (final c in companies)
        c.id: transactions
            .where((t) =>
                t.companyId == c.id &&
                t.type == TransactionType.income &&
                t.date.month == m.month &&
                t.date.year == m.year)
            .fold(0.0, (sum, t) => sum + t.amount),
    };
  }

  /// Monthly Expenses (Current Month) - uses local time for consistency with transaction dates
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
      double spent = 0.0;
      final categoryIds = _getCategoryAndDescendants(b.categoryId);
      for (final t in transactions) {
        if (t.type != TransactionType.expense) continue;
        if ('${t.date.year}-${t.date.month.toString().padLeft(2, '0')}' != b.monthYear) continue;

        if (t.splits.isNotEmpty) {
          // Use splits for categorization - they represent the breakdown
          for (final split in t.splits) {
            if (categoryIds.contains(split.categoryId)) {
              spent += split.amount;
            }
          }
        } else if (categoryIds.contains(t.categoryId)) {
          // No splits - use main transaction category (including subcategories)
          spent += t.amount;
        }
      }
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
    double total = 0.0;
    for (final p in recurringPayments) {
      // An expected incoming credit (e.g. a payday reminder) is not a
      // liability — it must not reduce Safe-to-Spend the way a bill does.
      if (p.isIncome) continue;
      // Calculate all occurrences within the next 30 days
      DateTime occurrence = p.nextDueDate;
      while (!occurrence.isAfter(cutoff)) {
        if (!occurrence.isBefore(now)) {
          total += p.amount;
        }
        occurrence = _addFrequency(occurrence, p.frequency);
        // Safety break to prevent infinite loop
        if (occurrence.isAfter(cutoff.add(const Duration(days: 365)))) break;
      }
    }
    return total;
  }

  DateTime _addFrequency(DateTime date, PaymentFrequency frequency) {
    switch (frequency) {
      case PaymentFrequency.daily:
        return date.add(const Duration(days: 1));
      case PaymentFrequency.weekly:
        return date.add(const Duration(days: 7));
      case PaymentFrequency.monthly:
        return DateTime(date.year, date.month + 1, date.day);
      case PaymentFrequency.quarterly:
        return DateTime(date.year, date.month + 3, date.day);
      case PaymentFrequency.yearly:
        return DateTime(date.year + 1, date.month, date.day);
    }
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
    List<CompanyModel>? companies,
    double? emergencyBuffer,
    String? currencySymbol,
    bool? isBiometricEnabled,
    bool? isRoundUpEnabled,
    bool? isAutoBackupEnabled,
    bool? isRefreshing,
    DateTime? lastRefreshedAt,
    Object? lastRefreshError = _sentinel,
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
      companies: companies ?? this.companies,
      emergencyBuffer: emergencyBuffer ?? this.emergencyBuffer,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isRoundUpEnabled: isRoundUpEnabled ?? this.isRoundUpEnabled,
      isAutoBackupEnabled: isAutoBackupEnabled ?? this.isAutoBackupEnabled,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      lastRefreshError: identical(lastRefreshError, _sentinel) ? this.lastRefreshError : lastRefreshError as String?,
    );
  }

  static const Object _sentinel = Object();
}

class FinanceNotifier extends StateNotifier<FinanceState> with CloudDirectWrite {
  final AppDatabase _db;

  AppDatabase get db => _db;

  /// Fired after every state change (wired by `financeNotifierProvider` to
  /// re-schedule payment reminders). Null in unit tests.
  void Function(FinanceState state)? onStateChanged;

  @override
  set state(FinanceState value) {
    super.state = value;
    onStateChanged?.call(value);
  }

  /// [autoLoad] is disabled in unit tests so state stays purely in-memory and
  /// synchronous, without racing an async DB read (or a cloud refresh) against
  /// the test body.
  FinanceNotifier(this._db, {bool autoLoad = true}) : super(_emptyState()) {
    if (autoLoad) {
      _loadPersistedState();
      SecretCipherService.readyListenable.addListener(_onCipherBecameReady);
    }
  }

  /// Whether the field-encryption DEK was already available the first time
  /// [_loadPersistedState] mapped rows. When it wasn't (a session-restore cold
  /// start — the async keystore read lost the race), [_onCipherBecameReady]
  /// re-reads once the DEK arrives so secret card / bank fields stop showing
  /// ciphertext.
  bool _cipherReadyOnLoad = false;

  void _onCipherBecameReady() {
    if (_cipherReadyOnLoad || !SecretCipherService.ready) return;
    _cipherReadyOnLoad = true;
    _loadPersistedState();
  }

  @override
  void dispose() {
    SecretCipherService.readyListenable.removeListener(_onCipherBecameReady);
    super.dispose();
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

  /// Ensures the local `categories` table isn't empty, seeding the default
  /// set if so. Idempotent. Called both from [_loadPersistedState] (on first
  /// widget-tree read of `financeNotifierProvider`) and from
  /// [refreshFromCloud] when the cloud has no categories yet for a brand-new
  /// user.
  static Future<void> ensureDefaultCategoriesSeeded(AppDatabase db) async {
    final existing = await (db.select(db.categories)
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return;
    for (final cat in _defaultCategories()) {
      await db.into(db.categories).insertOnConflictUpdate(cat.toCompanion());
    }
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
      companies: [],
    );
  }

  /// Re-reads everything from disk and replaces in-memory state. Used after
  /// a vault restore writes directly to the database, so the UI reflects the
  /// restored data without requiring an app restart.
  Future<void> reloadFromDb() => _loadPersistedState();

  /// Loads all persisted finance data (SQLite via Drift) and app-level
  /// settings (SharedPreferences) at startup so nothing is lost on restart —
  /// this is the *cache*, painted instantly. Once it's in, a full refresh
  /// from the cloud is kicked off in the background (fire-and-forget; it has
  /// its own error handling and never touches state on failure).
  Future<void> _loadPersistedState() async {
    try {
      // Bring the field-encryption DEK back from the OS keystore so sensitive
      // card / bank values decrypt transparently after an app relaunch.
      await SecretCipherService(_db).restoreFromCache();
      _cipherReadyOnLoad = _cipherReadyOnLoad || SecretCipherService.ready;

      final accounts = (await (_db.select(_db.accounts)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      var categories = (await (_db.select(_db.categories)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      final transactions = (await (_db.select(_db.transactions)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final creditCards = (await (_db.select(_db.creditCards)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      final loans = (await (_db.select(_db.loans)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      final budgets = (await (_db.select(_db.budgets)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      final recurringPayments =
          (await (_db.select(_db.recurringPayments)..where((t) => t.isDeleted.equals(false))).get())
              .map((e) => e.toModel())
              .toList();
      final investments = (await (_db.select(_db.investments)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      final goals = (await (_db.select(_db.goals)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();
      final companies = (await (_db.select(_db.companies)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList();

      if (categories.isEmpty) {
        await ensureDefaultCategoriesSeeded(_db);
        categories = _defaultCategories();
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
        companies: companies,
        emergencyBuffer: prefs.getDouble(_kEmergencyBuffer) ?? 20000.0,
        currencySymbol: prefs.getString(_kCurrencySymbol) ?? '₹',
        isBiometricEnabled: prefs.getBool(_kBiometricEnabled) ?? false,
        isRoundUpEnabled: prefs.getBool(_kRoundUpEnabled) ?? false,
        isAutoBackupEnabled: prefs.getBool(_kAutoBackupEnabled) ?? false,
      );
      // Push persisted symbol into the static formatter immediately.
      CurrencyFormatter.updateSymbol(state.currencySymbol);

      // Local cache is on screen — now reconcile with the cloud in the
      // background. No-ops instantly for demo/offline accounts.
      if (hasCloudSession) unawaited(refreshFromCloud());
    } catch (e, st) {
      debugPrint('FinanceNotifier: failed to load persisted data: $e\n$st');
    }
  }

  // ── Refresh from cloud ──────────────────────────────────────────────────
  //
  // There is no realtime subscription and no periodic timer any more — cross-
  // device convergence happens on next launch, app resume, or a manual
  // "Refresh now" (see Settings), not live. [refreshFromCloud] fetches every
  // table to completion *before* touching the local cache, so a failure
  // partway through (network drop, paused project) leaves the existing cache
  // untouched and only sets [FinanceState.lastRefreshError] — never a
  // half-replaced table.
  bool get isRefreshingFromCloud => state.isRefreshing;

  Future<void> refreshFromCloud() async {
    if (!hasCloudSession || state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, lastRefreshError: null);
    try {
      final fetched = <String, List<Map<String, dynamic>>>{};
      for (final table in _financeCloudTables) {
        fetched[table] = await _fetchAllPages(table);
      }

      CloudSettings? settings;
      try {
        final row = await SupabaseService.client.from('user_settings').select().maybeSingle();
        if (row != null) settings = CloudSettings.fromCloud(row);
      } catch (e) {
        // Settings are a "nice to have" here — a fetch failure for this one
        // row must not abort the (already-fetched) entity refresh.
        debugPrint('FinanceNotifier.refreshFromCloud: settings fetch failed: $e');
      }

      // Every page of every table arrived — now replace the cache atomically.
      await _db.transaction(() async {
        await _db.delete(_db.accounts).go();
        for (final r in fetched['accounts']!) {
          await _db.into(_db.accounts).insertOnConflictUpdate(AccountCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.categories).go();
        for (final r in fetched['categories']!) {
          await _db.into(_db.categories).insertOnConflictUpdate(CategoryCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.transactions).go();
        for (final r in fetched['transactions']!) {
          await _db.into(_db.transactions).insertOnConflictUpdate(TransactionCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.creditCards).go();
        for (final r in fetched['credit_cards']!) {
          await _db.into(_db.creditCards).insertOnConflictUpdate(CardCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.loans).go();
        for (final r in fetched['loans']!) {
          await _db.into(_db.loans).insertOnConflictUpdate(LoanCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.budgets).go();
        for (final r in fetched['budgets']!) {
          await _db.into(_db.budgets).insertOnConflictUpdate(BudgetCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.recurringPayments).go();
        for (final r in fetched['recurring_payments']!) {
          await _db.into(_db.recurringPayments).insertOnConflictUpdate(RecurringPaymentCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.investments).go();
        for (final r in fetched['investments']!) {
          await _db.into(_db.investments).insertOnConflictUpdate(InvestmentCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.goals).go();
        for (final r in fetched['goals']!) {
          await _db.into(_db.goals).insertOnConflictUpdate(GoalCloud.fromCloud(r).toCompanion());
        }
        await _db.delete(_db.companies).go();
        for (final r in fetched['companies']!) {
          await _db.into(_db.companies).insertOnConflictUpdate(CompanyCloud.fromCloud(r).toCompanion());
        }
      });

      var categories = fetched['categories']!.map(CategoryCloud.fromCloud).toList();
      if (categories.isEmpty) {
        // Brand-new user: the cloud genuinely has none yet — seed + persist
        // the defaults so this device (and future ones) start consistent.
        await ensureDefaultCategoriesSeeded(_db);
        categories = _defaultCategories();
      }

      state = state.copyWith(
        accounts: fetched['accounts']!.map(AccountCloud.fromCloud).toList(),
        categories: categories,
        transactions: fetched['transactions']!.map(TransactionCloud.fromCloud).toList()
          ..sort((a, b) => b.date.compareTo(a.date)),
        creditCards: fetched['credit_cards']!.map(CardCloud.fromCloud).toList(),
        loans: fetched['loans']!.map(LoanCloud.fromCloud).toList(),
        budgets: fetched['budgets']!.map(BudgetCloud.fromCloud).toList(),
        recurringPayments: fetched['recurring_payments']!.map(RecurringPaymentCloud.fromCloud).toList(),
        investments: fetched['investments']!.map(InvestmentCloud.fromCloud).toList(),
        goals: fetched['goals']!.map(GoalCloud.fromCloud).toList(),
        companies: fetched['companies']!.map(CompanyCloud.fromCloud).toList(),
        emergencyBuffer: settings?.emergencyBuffer,
        currencySymbol: settings?.currencySymbol,
        isRoundUpEnabled: settings?.isRoundUpEnabled,
        isAutoBackupEnabled: settings?.isAutoBackupEnabled,
        isRefreshing: false,
        lastRefreshedAt: DateTime.now(),
        lastRefreshError: null,
      );

      if (settings != null) {
        CurrencyFormatter.updateSymbol(settings.currencySymbol);
        _fireAndForget(() async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(_kEmergencyBuffer, settings!.emergencyBuffer);
          await prefs.setString(_kCurrencySymbol, settings.currencySymbol);
          await prefs.setBool(_kRoundUpEnabled, settings.isRoundUpEnabled);
          await prefs.setBool(_kAutoBackupEnabled, settings.isAutoBackupEnabled);
        }, 'persist refreshed settings');
        // Adopt the cloud DEK key material only when this device has none yet
        // (first-writer-wins: a device that already provisioned keeps its own).
        _fireAndForget(() async {
          Future<void> adopt(String key, String? value) async {
            if (value == null) return;
            final existing =
                await (_db.select(_db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull();
            if (existing == null) {
              await _db.into(_db.syncMeta).insertOnConflictUpdate(
                    SyncMetaCompanion(key: Value(key), value: Value(value)),
                  );
            }
          }

          await adopt('sec_wrapped_dek', settings!.secWrappedDek);
          await adopt('sec_kek_salt', settings.secKekSalt);
          await adopt('sec_wrapped_dek_rc', settings.secWrappedDekRc);
          await adopt('sec_rc_salt', settings.secRcSalt);
        }, 'adopt cloud DEK key material');
      }
    } catch (e, st) {
      debugPrint('FinanceNotifier.refreshFromCloud failed: $e\n$st');
      // Leave the existing cache exactly as it was — only note the failure.
      state = state.copyWith(isRefreshing: false, lastRefreshError: e.toString());
    }
  }

  /// Paginated full-table fetch (RLS already scopes rows to the signed-in
  /// user, so no explicit `user_id` filter is needed — mirrors the old
  /// `SupabaseCloudGateway.pull`).
  Future<List<Map<String, dynamic>>> _fetchAllPages(String table) async {
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      // A stable order is required, not cosmetic: .range() is only a safe
      // pagination cursor over a deterministically-ordered result set —
      // without it Postgres is free to return rows in any order per page,
      // which can silently skip or duplicate rows across pages for a user
      // with more than one page of data.
      final page = await SupabaseService.client
          .from(table)
          .select()
          .eq('is_deleted', false)
          .order('created_at')
          .range(offset, offset + _kRefreshPageSize - 1);
      final list = (page as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      rows.addAll(list);
      if (list.length < _kRefreshPageSize) break;
      offset += _kRefreshPageSize;
    }
    return rows;
  }

  /// Pushes every locally-held (non-deleted) row straight to the cloud —
  /// used after a vault restore writes rows directly into Drift, bypassing
  /// every mutator, so the cloud copy converges with the restored data.
  /// Best-effort per row: one failing row is logged and skipped rather than
  /// aborting the whole push (the user already has the data locally either
  /// way, and a partial cloud copy is still strictly better than none).
  Future<void> pushAllToCloud() async {
    if (!hasCloudSession) return;
    Future<void> pushAll<T>(String table, List<T> rows, Map<String, dynamic> Function(T) toJson) async {
      for (final row in rows) {
        try {
          await pushToCloud(table, toJson(row));
        } catch (e) {
          debugPrint('FinanceNotifier.pushAllToCloud($table) row failed: $e');
        }
      }
    }

    await pushAll('accounts', state.accounts, (a) => a.toCloudJson());
    await pushAll('categories', state.categories, (c) => c.toCloudJson());
    await pushAll('transactions', state.transactions, (t) => t.toCloudJson());
    await pushAll('credit_cards', state.creditCards, (c) => c.toCloudJson());
    await pushAll('loans', state.loans, (l) => l.toCloudJson());
    await pushAll('budgets', state.budgets, (b) => b.toCloudJson());
    await pushAll('recurring_payments', state.recurringPayments, (p) => p.toCloudJson());
    await pushAll('investments', state.investments, (i) => i.toCloudJson());
    await pushAll('goals', state.goals, (g) => g.toCloudJson());
    await pushAll('companies', state.companies, (c) => c.toCloudJson());
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

  // ── Undo-delete window ─────────────────────────────────────────────────────
  // A just-deleted entity is soft-deleted (tombstoned) both in the cloud and
  // locally. For a short window we keep the last serialized copy so an "Undo"
  // on the confirmation SnackBar can fully reverse it — re-upsert it to the
  // cloud with `is_deleted: false` and restore it locally. Entries are pruned
  // by age (no timers, so nothing outlives a test).
  static const Duration _undoWindow = Duration(seconds: 8);
  final Map<String, ({Map<String, dynamic> row, DateTime at})> _recentlyDeleted = {};

  void _stashDeleted(String table, Map<String, dynamic> cloudRow) {
    final now = DateTime.now();
    _recentlyDeleted.removeWhere((_, v) => now.difference(v.at) > _undoWindow);
    _recentlyDeleted['$table:${cloudRow['id']}'] = (row: cloudRow, at: now);
  }

  /// True while an "Undo" is still offerable for `(table, id)`.
  bool canUndoDelete(String table, String id) {
    final s = _recentlyDeleted['$table:$id'];
    return s != null && DateTime.now().difference(s.at) <= _undoWindow;
  }

  /// Reverses a just-performed entity delete. Wired to the "Undo" action on the
  /// post-delete SnackBar. No-op once the window has passed. Best-effort: a
  /// failure here is logged rather than surfaced, since by this point the
  /// delete itself already succeeded and the row is truly gone from the
  /// user's perspective — the "Undo" affordance is a courtesy, not the
  /// primary write path.
  Future<void> undoDelete(String table, String id) async {
    final key = '$table:$id';
    final stash = _recentlyDeleted.remove(key);
    if (stash == null || DateTime.now().difference(stash.at) > _undoWindow) return;
    try {
      final row = Map<String, dynamic>.from(stash.row)
        ..['is_deleted'] = false
        ..['deleted_at'] = null
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
      final serverTs = await pushToCloud(table, row);
      if (serverTs != null) row['updated_at'] = serverTs.toUtc().toIso8601String();
      await _applyRowLocally(table, row);
    } catch (e) {
      debugPrint('FinanceNotifier.undoDelete failed: $e');
    }
  }

  /// Writes a cloud-shaped row (already un-deleted) to Drift and splices it
  /// into the matching in-memory list. Used only by [undoDelete].
  Future<void> _applyRowLocally(String table, Map<String, dynamic> row) async {
    switch (table) {
      case 'accounts':
        final m = AccountCloud.fromCloud(row);
        await _db.into(_db.accounts).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(accounts: _spliceById(state.accounts, m, (a) => a.id, false));
        break;
      case 'categories':
        final m = CategoryCloud.fromCloud(row);
        await _db.into(_db.categories).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(categories: _spliceById(state.categories, m, (c) => c.id, false));
        break;
      case 'transactions':
        final m = TransactionCloud.fromCloud(row);
        await _db.into(_db.transactions).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(
          transactions: _spliceById(state.transactions, m, (t) => t.id, false)
            ..sort((a, b) => b.date.compareTo(a.date)),
        );
        break;
      case 'credit_cards':
        final m = CardCloud.fromCloud(row);
        await _db.into(_db.creditCards).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(creditCards: _spliceById(state.creditCards, m, (c) => c.id, false));
        break;
      case 'loans':
        final m = LoanCloud.fromCloud(row);
        await _db.into(_db.loans).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(loans: _spliceById(state.loans, m, (l) => l.id, false));
        break;
      case 'budgets':
        final m = BudgetCloud.fromCloud(row);
        await _db.into(_db.budgets).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(budgets: _spliceById(state.budgets, m, (b) => b.id, false));
        break;
      case 'recurring_payments':
        final m = RecurringPaymentCloud.fromCloud(row);
        await _db.into(_db.recurringPayments).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(recurringPayments: _spliceById(state.recurringPayments, m, (p) => p.id, false));
        break;
      case 'investments':
        final m = InvestmentCloud.fromCloud(row);
        await _db.into(_db.investments).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(investments: _spliceById(state.investments, m, (i) => i.id, false));
        break;
      case 'goals':
        final m = GoalCloud.fromCloud(row);
        await _db.into(_db.goals).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(goals: _spliceById(state.goals, m, (g) => g.id, false));
        break;
      case 'companies':
        final m = CompanyCloud.fromCloud(row);
        await _db.into(_db.companies).insertOnConflictUpdate(m.toCompanion());
        state = state.copyWith(companies: _spliceById(state.companies, m, (c) => c.id, false));
        break;
      default:
        debugPrint('FinanceNotifier._applyRowLocally: unknown table "$table"');
    }
  }

  static List<T> _spliceById<T>(List<T> list, T item, String Function(T) idOf, bool removed) {
    final id = idOf(item);
    final next = list.where((e) => idOf(e) != id).toList();
    if (!removed) next.add(item);
    return next;
  }

  // --- Actions & State Modifiers ---
  //
  // Every mutator below pushes to Supabase first (via `pushToCloud`, from
  // [CloudDirectWrite]) and only writes to local Drift / in-memory `state`
  // once that push has succeeded (or there is no cloud session at all, e.g.
  // a demo account — see [CloudDirectWrite.hasCloudSession]). A failed push
  // throws [CloudWriteException] before anything local changes; the calling
  // UI screen awaits and shows the error. There is no offline queue any
  // more: a mutation now requires connectivity.

  Future<void> addTransaction({
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
    String? investmentId,
    String? companyId,
    bool isExternalToAccount = false,
    bool isOnline = true,
  }) async {
    final now = DateTime.now();
    final draftTx = TransactionModel(
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
      investmentId: investmentId,
      companyId: companyId,
      isExternalToAccount: isExternalToAccount,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    // Credit card outstanding management. Only *credit* cards carry an
    // `currentOutstanding` — a debit-card spend is just an expense on the
    // linked bank account (tx.accountId == card.linkedAccountId), so
    // `accountsWithCalculatedBalances` already subtracts it and this block
    // must be a no-op for debit / prepaid / store / forex cards.
    CreditCardModel? adjustedCard;
    if (creditCardId != null) {
      final cardIdx = state.creditCards.indexWhere((c) => c.id == creditCardId);
      if (cardIdx != -1 && state.creditCards[cardIdx].cardType == CardType.credit) {
        final card = state.creditCards[cardIdx];
        double newOutstanding = card.currentOutstanding;

        if (type == TransactionType.creditCardPayment) {
          // Payment reduces outstanding; can't go below zero (overpayment).
          newOutstanding = (card.currentOutstanding - amount).clamp(0.0, double.infinity);
        } else if (type == TransactionType.expense) {
          // Spending charges to card increases outstanding. Not capped at
          // creditLimit — real cards can go over-limit; silently discarding
          // the excess would understate actual debt owed.
          newOutstanding = card.currentOutstanding + amount;
        } else if (type == TransactionType.refund) {
          // Refund reduces outstanding (money back to card).
          newOutstanding = (card.currentOutstanding - amount).clamp(0.0, double.infinity);
        }

        adjustedCard = card.copyWith(
          currentOutstanding: newOutstanding,
          // Recording the bill payment lets payment_reminders.dart suppress
          // this cycle's due-date nudges.
          lastPaymentDate: type == TransactionType.creditCardPayment ? date : null,
          lastPaymentAmount: type == TransactionType.creditCardPayment ? amount : null,
          updatedAt: now,
        );
      }
    }

    // If loan payment transfer
    LoanModel? adjustedLoan;
    if (type == TransactionType.loanPayment && loanId != null) {
      final loanIdx = state.loans.indexWhere((l) => l.id == loanId);
      if (loanIdx != -1) {
        final loan = state.loans[loanIdx];
        final newOutstanding = (loan.outstandingAmount - amount).clamp(0.0, loan.principalAmount);
        // Only decrement tenure for scheduled EMI payments (amount matches monthlyEmi)
        // Extra payments don't reduce tenure - they just reduce outstanding
        final isScheduledEmi = (amount - loan.monthlyEmi).abs() < 0.01;
        final newTenure = isScheduledEmi && loan.remainingTenureMonths > 0
            ? loan.remainingTenureMonths - 1
            : loan.remainingTenureMonths;
        adjustedLoan = LoanModel(
          id: loan.id,
          name: loan.name,
          provider: loan.provider,
          principalAmount: loan.principalAmount,
          outstandingAmount: newOutstanding,
          interestRate: loan.interestRate,
          monthlyEmi: loan.monthlyEmi,
          dueDay: loan.dueDay,
          startDate: loan.startDate,
          remainingTenureMonths: newTenure,
          updatedAt: now,
        );
      }
    }

    // If investment transaction - update/create InvestmentModel
    InvestmentModel? adjustedInvestment;
    if (type == TransactionType.investment && investmentId != null) {
      final invIdx = state.investments.indexWhere((i) => i.id == investmentId);
      if (invIdx != -1) {
        final inv = state.investments[invIdx];
        adjustedInvestment = InvestmentModel(
          id: inv.id,
          name: inv.name,
          type: inv.type,
          investedAmount: inv.investedAmount + amount,
          currentValue: inv.currentValue + amount, // Assume current value increases by invested amount
          monthlySipAmount: inv.monthlySipAmount,
          sipDay: inv.sipDay,
          updatedAt: now,
        );
      }
    }

    // Push everything to the cloud first (sequentially) — nothing local
    // changes unless every push that's needed succeeds, so a mid-way failure
    // can never leave the ledger and a card/loan/investment balance out of
    // step with each other.
    final txTs = await pushToCloud('transactions', draftTx.toCloudJson());
    final cardTs = adjustedCard == null ? null : await pushToCloud('credit_cards', adjustedCard.toCloudJson());
    final loanTs = adjustedLoan == null ? null : await pushToCloud('loans', adjustedLoan.toCloudJson());
    final invTs = adjustedInvestment == null ? null : await pushToCloud('investments', adjustedInvestment.toCloudJson());

    final savedTx = txTs != null ? draftTx.copyWith(updatedAt: txTs) : draftTx;
    final savedCard = adjustedCard == null ? null : (cardTs != null ? adjustedCard.copyWith(updatedAt: cardTs) : adjustedCard);
    final savedLoan = adjustedLoan == null
        ? null
        : (loanTs == null
            ? adjustedLoan
            : LoanModel(
                id: adjustedLoan.id, name: adjustedLoan.name, provider: adjustedLoan.provider,
                principalAmount: adjustedLoan.principalAmount, outstandingAmount: adjustedLoan.outstandingAmount,
                interestRate: adjustedLoan.interestRate, monthlyEmi: adjustedLoan.monthlyEmi, dueDay: adjustedLoan.dueDay,
                startDate: adjustedLoan.startDate, remainingTenureMonths: adjustedLoan.remainingTenureMonths,
                updatedAt: loanTs,
              ));
    final savedInvestment = adjustedInvestment == null
        ? null
        : (invTs == null
            ? adjustedInvestment
            : InvestmentModel(
                id: adjustedInvestment.id, name: adjustedInvestment.name, type: adjustedInvestment.type,
                investedAmount: adjustedInvestment.investedAmount, currentValue: adjustedInvestment.currentValue,
                monthlySipAmount: adjustedInvestment.monthlySipAmount, sipDay: adjustedInvestment.sipDay,
                updatedAt: invTs,
              ));

    await _db.into(_db.transactions).insertOnConflictUpdate(savedTx.toCompanion());
    if (savedCard != null) await _db.into(_db.creditCards).insertOnConflictUpdate(savedCard.toCompanion());
    if (savedLoan != null) await _db.into(_db.loans).insertOnConflictUpdate(savedLoan.toCompanion());
    if (savedInvestment != null) await _db.into(_db.investments).insertOnConflictUpdate(savedInvestment.toCompanion());

    state = state.copyWith(
      transactions: [savedTx, ...state.transactions],
      creditCards: savedCard != null ? _spliceById(state.creditCards, savedCard, (c) => c.id, false) : state.creditCards,
      loans: savedLoan != null ? _spliceById(state.loans, savedLoan, (l) => l.id, false) : state.loans,
      investments:
          savedInvestment != null ? _spliceById(state.investments, savedInvestment, (i) => i.id, false) : state.investments,
    );
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
      _fireAndForget(
          () => _db.into(_db.transactions).insertOnConflictUpdate(updated!.toCompanion()),
          'transaction sync status');
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
  Future<void> updateTransaction(String id, {
    double? amount,
    String? categoryId,
    String? merchant,
    DateTime? date,
    String? description,
    String? notes,
    List<String>? tags,
  }) async {
    final match = state.transactions.where((t) => t.id == id).toList();
    if (match.isEmpty) return; // nothing to update — treat as a no-op
    final original = match.first;
    final newAmount = amount ?? original.amount;
    final delta = newAmount - original.amount;
    final now = DateTime.now();

    final draft = original.copyWith(
      amount: newAmount,
      categoryId: categoryId ?? original.categoryId,
      merchant: merchant ?? original.merchant,
      date: date ?? original.date,
      description: description ?? original.description,
      notes: notes ?? original.notes,
      tags: tags ?? original.tags,
      updatedAt: now,
    );

    CreditCardModel? adjustedCard;
    if (delta != 0 && original.creditCardId != null) {
      final cardIdx = state.creditCards.indexWhere((c) => c.id == original.creditCardId);
      // Debit / prepaid / store / forex cards have no `currentOutstanding`;
      // their spend lives on the linked account and needs no adjustment here.
      if (cardIdx != -1 && state.creditCards[cardIdx].cardType == CardType.credit) {
        final card = state.creditCards[cardIdx];
        int sign;
        if (original.type == TransactionType.creditCardPayment || original.type == TransactionType.refund) {
          sign = -1; // Payment or refund reduces outstanding
        } else {
          sign = 1; // Expense increases outstanding
        }
        final newOutstanding = (card.currentOutstanding + (delta * sign)).clamp(0.0, double.infinity);
        adjustedCard = card.copyWith(currentOutstanding: newOutstanding, updatedAt: now);
      }
    }

    LoanModel? adjustedLoan;
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
          updatedAt: now,
        );
      }
    }

    final txTs = await pushToCloud('transactions', draft.toCloudJson());
    final cardTs = adjustedCard == null ? null : await pushToCloud('credit_cards', adjustedCard.toCloudJson());
    final loanTs = adjustedLoan == null ? null : await pushToCloud('loans', adjustedLoan.toCloudJson());

    final savedTx = txTs != null ? draft.copyWith(updatedAt: txTs) : draft;
    final savedCard = adjustedCard == null ? null : (cardTs != null ? adjustedCard.copyWith(updatedAt: cardTs) : adjustedCard);
    final savedLoan = adjustedLoan == null
        ? null
        : (loanTs == null
            ? adjustedLoan
            : LoanModel(
                id: adjustedLoan.id, name: adjustedLoan.name, provider: adjustedLoan.provider,
                principalAmount: adjustedLoan.principalAmount, outstandingAmount: adjustedLoan.outstandingAmount,
                interestRate: adjustedLoan.interestRate, monthlyEmi: adjustedLoan.monthlyEmi, dueDay: adjustedLoan.dueDay,
                startDate: adjustedLoan.startDate, remainingTenureMonths: adjustedLoan.remainingTenureMonths,
                updatedAt: loanTs,
              ));

    await _db.into(_db.transactions).insertOnConflictUpdate(savedTx.toCompanion());
    if (savedCard != null) await _db.into(_db.creditCards).insertOnConflictUpdate(savedCard.toCompanion());
    if (savedLoan != null) await _db.into(_db.loans).insertOnConflictUpdate(savedLoan.toCompanion());

    state = state.copyWith(
      transactions: state.transactions.map((t) => t.id == id ? savedTx : t).toList(),
      creditCards: savedCard != null ? _spliceById(state.creditCards, savedCard, (c) => c.id, false) : state.creditCards,
      loans: savedLoan != null ? _spliceById(state.loans, savedLoan, (l) => l.id, false) : state.loans,
    );
  }

  Future<void> addAccount({
    required String name,
    required AccountType type,
    String? bank,
    String? accountNumberLast4,
    required double openingBalance,
    String? encAccountNumber,
    String? encIfsc,
  }) async {
    final now = DateTime.now();
    final draft = AccountModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      bank: bank,
      accountNumberLast4: accountNumberLast4,
      openingBalance: openingBalance,
      calculatedBalance: openingBalance,
      createdAt: now,
      updatedAt: now,
      encAccountNumber: encAccountNumber,
      encIfsc: encIfsc,
    );

    final serverTs = await pushToCloud('accounts', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.accounts).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(accounts: [...state.accounts, saved]);
  }

  Future<void> addCard({
    required CardType cardType,
    required String name,
    required String bank,
    required String last4,
    required String cardholderName,
    CardNetwork network = CardNetwork.visa,
    int? expiryMonth,
    int? expiryYear,
    CardColorPreset colorPreset = CardColorPreset.midnight,
    String? colorHex,
    bool isVirtual = false,
    String? notes,
    // Encrypted sensitive details (AES-GCM ciphertext blobs, never plaintext).
    String? encCardNumber,
    String? encCvv,
    String? encPin,
    // Credit-card fields
    double creditLimit = 0,
    int statementDay = 1,
    int dueDay = 15,
    String? linkedAccountId,
    // Prepaid / forex fields
    double? balance,
    String? currency,
  }) async {
    final draft = CardModel(
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
      colorHex: colorHex,
      isVirtual: isVirtual,
      notes: notes,
      encCardNumber: encCardNumber,
      encCvv: encCvv,
      encPin: encPin,
      creditLimit: creditLimit,
      currentOutstanding: 0.0,
      statementDay: statementDay,
      dueDay: dueDay,
      linkedAccountId: linkedAccountId,
      balance: balance,
      currency: currency,
    );

    final serverTs = await pushToCloud('credit_cards', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.creditCards).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(creditCards: [...state.creditCards, saved]);
  }

  /// Backward-compat wrapper so existing calls compile
  Future<void> addCreditCard({
    required String name,
    required String bank,
    required String last4,
    required double creditLimit,
    required int statementDay,
    required int dueDay,
    String cardholderName = '',
  }) {
    return addCard(
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

  Future<void> updateCard(String cardId, {
    String? name,
    String? bank,
    String? last4,
    String? cardholderName,
    CardNetwork? network,
    int? expiryMonth,
    int? expiryYear,
    CardColorPreset? colorPreset,
    String? colorHex,
    String? notes,
    String? encCardNumber,
    String? encCvv,
    String? encPin,
    double? creditLimit,
    double? currentOutstanding,
    int? statementDay,
    int? dueDay,
    String? linkedAccountId,
    double? balance,
    String? currency,
    DateTime? lastPaymentDate,
    double? lastPaymentAmount,
  }) async {
    final existing = state.creditCards.where((c) => c.id == cardId).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(
      name: name,
      bank: bank,
      last4: last4,
      cardholderName: cardholderName,
      network: network,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      colorPreset: colorPreset,
      colorHex: colorHex,
      notes: notes,
      encCardNumber: encCardNumber,
      encCvv: encCvv,
      encPin: encPin,
      creditLimit: creditLimit,
      currentOutstanding: currentOutstanding,
      statementDay: statementDay,
      dueDay: dueDay,
      linkedAccountId: linkedAccountId,
      balance: balance,
      currency: currency,
      lastPaymentDate: lastPaymentDate,
      lastPaymentAmount: lastPaymentAmount,
    );

    final serverTs = await pushToCloud('credit_cards', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.creditCards).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(creditCards: state.creditCards.map((c) => c.id == cardId ? saved : c).toList());
  }

  Future<void> deleteCard(String cardId) async {
    final gone = state.creditCards.where((c) => c.id == cardId).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = gone.first.copyWith(isDeleted: true, updatedAt: now);

    await pushToCloud('credit_cards', tombstone.toCloudJson());
    _stashDeleted('credit_cards', gone.first.toCloudJson());

    await (_db.update(_db.creditCards)..where((c) => c.id.equals(cardId))).write(
      CreditCardsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(creditCards: state.creditCards.where((c) => c.id != cardId).toList());
  }

  Future<void> addLoan({
    required String name,
    required String provider,
    required double principalAmount,
    required double interestRate,
    required double monthlyEmi,
    required int dueDay,
    required int tenureMonths,
  }) async {
    final draft = LoanModel(
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

    final serverTs = await pushToCloud('loans', draft.toCloudJson());
    final saved = serverTs == null
        ? draft
        : LoanModel(
            id: draft.id, name: draft.name, provider: draft.provider,
            principalAmount: draft.principalAmount, outstandingAmount: draft.outstandingAmount,
            interestRate: draft.interestRate, monthlyEmi: draft.monthlyEmi, dueDay: draft.dueDay,
            startDate: draft.startDate, remainingTenureMonths: draft.remainingTenureMonths,
            updatedAt: serverTs,
          );

    await _db.into(_db.loans).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(loans: [...state.loans, saved]);
  }

  Future<void> addInvestment({
    required String name,
    required InvestmentType type,
    required double investedAmount,
    required double currentValue,
    double monthlySipAmount = 0.0,
    int sipDay = 1,
    String? referenceNumber,
  }) async {
    final draft = InvestmentModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      investedAmount: investedAmount,
      currentValue: currentValue,
      monthlySipAmount: monthlySipAmount,
      sipDay: sipDay,
      referenceNumber: referenceNumber,
    );

    final serverTs = await pushToCloud('investments', draft.toCloudJson());
    final saved = serverTs == null ? draft : draft.copyWith(updatedAt: serverTs);

    await _db.into(_db.investments).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(investments: [...state.investments, saved]);
  }

  Future<void> addGoal({
    required String name,
    required double targetAmount,
    required double currentSavedAmount,
    DateTime? targetDate,
    String icon = 'target',
  }) async {
    final draft = GoalModel(
      id: _uuid.v4(),
      name: name,
      targetAmount: targetAmount,
      currentSavedAmount: currentSavedAmount,
      targetDate: targetDate,
      icon: icon,
    );

    final serverTs = await pushToCloud('goals', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.goals).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(goals: [...state.goals, saved]);
  }

  Future<void> addFundsToGoal(String goalId, double amount) async {
    final existing = state.goals.where((g) => g.id == goalId).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(currentSavedAmount: existing.first.currentSavedAmount + amount);

    final serverTs = await pushToCloud('goals', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.goals).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(goals: state.goals.map((g) => g.id == goalId ? saved : g).toList());
  }

  Future<void> deleteGoal(String id) async {
    final gone = state.goals.where((g) => g.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = gone.first.copyWith(isDeleted: true, updatedAt: now);

    await pushToCloud('goals', tombstone.toCloudJson());
    _stashDeleted('goals', gone.first.toCloudJson());

    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(goals: state.goals.where((g) => g.id != id).toList());
  }

  // ── Companies (employers) ────────────────────────────────────────────────

  Future<void> addCompany({
    required String name,
    DateTime? joinedDate,
    bool isCurrentEmployer = false,
    String? defaultBankAccountId,
    double? defaultPfAmount,
  }) async {
    final draft = CompanyModel(
      id: _uuid.v4(),
      name: name,
      joinedDate: joinedDate,
      isCurrentEmployer: isCurrentEmployer,
      defaultBankAccountId: defaultBankAccountId,
      defaultPfAmount: defaultPfAmount,
    );

    final serverTs = await pushToCloud('companies', draft.toCloudJson());
    var saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.companies).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(companies: [...state.companies, saved]);

    if (isCurrentEmployer) await setCurrentEmployer(saved.id);
  }

  Future<void> updateCompany(
    String id, {
    String? name,
    DateTime? joinedDate,
    String? defaultBankAccountId,
    double? defaultPfAmount,
  }) async {
    final existing = state.companies.where((c) => c.id == id).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(
      name: name,
      joinedDate: joinedDate,
      defaultBankAccountId: defaultBankAccountId,
      defaultPfAmount: defaultPfAmount,
    );

    final serverTs = await pushToCloud('companies', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.companies).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(companies: state.companies.map((c) => c.id == id ? saved : c).toList());
  }

  /// Marks [id] as the current employer and every other company as not —
  /// the "switch jobs" action. Pushes every changed row before touching
  /// local state, same as every other mutator here; a partial failure logs
  /// and stops rather than leaving two companies marked current.
  Future<void> setCurrentEmployer(String id) async {
    if (!state.companies.any((c) => c.id == id)) return;
    final now = DateTime.now();
    final updated = <CompanyModel>[];
    for (final c in state.companies) {
      final shouldBeCurrent = c.id == id;
      if (c.isCurrentEmployer == shouldBeCurrent) {
        updated.add(c);
        continue;
      }
      final draft = c.copyWith(isCurrentEmployer: shouldBeCurrent, updatedAt: now);
      final serverTs = await pushToCloud('companies', draft.toCloudJson());
      final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;
      await _db.into(_db.companies).insertOnConflictUpdate(saved.toCompanion());
      updated.add(saved);
    }
    state = state.copyWith(companies: updated);
  }

  Future<void> deleteCompany(String id) async {
    final gone = state.companies.where((c) => c.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = gone.first.copyWith(isDeleted: true, updatedAt: now);

    await pushToCloud('companies', tombstone.toCloudJson());
    _stashDeleted('companies', gone.first.toCloudJson());

    await (_db.update(_db.companies)..where((c) => c.id.equals(id))).write(
      CompaniesCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(companies: state.companies.where((c) => c.id != id).toList());
  }

  // ── Salary logging ────────────────────────────────────────────────────────

  /// Logs a salary credit: an income transaction for the net amount credited
  /// to [bankAccountId], plus — if [pfContribution] is given — a linked
  /// investment-type transaction that bumps [pfInvestmentId]'s balance
  /// without touching the bank account (see accountsWithCalculatedBalances'
  /// `isExternalToAccount` handling: that money was diverted by the employer
  /// before it ever reached the bank).
  Future<void> logSalary({
    required String companyId,
    required String bankAccountId,
    required double netAmount,
    double? pfContribution,
    String? pfInvestmentId,
    required DateTime date,
    String? notes,
  }) async {
    // Built as one atomic push-then-write, same shape as addTransaction's own
    // transaction+side-effect bundling — two separate addTransaction() calls
    // would let the net-credit succeed while the PF leg fails (or vice
    // versa), leaving a half-logged salary with no way to tell from the UI.
    final now = DateTime.now();
    final hasPf = pfContribution != null && pfContribution > 0 && pfInvestmentId != null;

    final incomeDraft = TransactionModel(
      id: _uuid.v4(),
      accountId: bankAccountId,
      type: TransactionType.income,
      amount: netAmount,
      categoryId: 'cat_salary',
      date: date,
      notes: notes,
      companyId: companyId,
      createdAt: now,
      updatedAt: now,
    );

    TransactionModel? pfDraft;
    InvestmentModel? adjustedInvestment;
    if (hasPf) {
      pfDraft = TransactionModel(
        id: _uuid.v4(),
        accountId: bankAccountId,
        type: TransactionType.investment,
        amount: pfContribution,
        date: date,
        investmentId: pfInvestmentId,
        companyId: companyId,
        isExternalToAccount: true,
        createdAt: now,
        updatedAt: now,
      );
      final invIdx = state.investments.indexWhere((i) => i.id == pfInvestmentId);
      if (invIdx != -1) {
        final inv = state.investments[invIdx];
        adjustedInvestment = inv.copyWith(
          investedAmount: inv.investedAmount + pfContribution,
          currentValue: inv.currentValue + pfContribution,
          updatedAt: now,
        );
      }
    }

    final incomeTs = await pushToCloud('transactions', incomeDraft.toCloudJson());
    final pfTs = pfDraft == null ? null : await pushToCloud('transactions', pfDraft.toCloudJson());
    final invTs = adjustedInvestment == null ? null : await pushToCloud('investments', adjustedInvestment.toCloudJson());

    final savedIncome = incomeTs != null ? incomeDraft.copyWith(updatedAt: incomeTs) : incomeDraft;
    final savedPf = pfDraft == null ? null : (pfTs != null ? pfDraft.copyWith(updatedAt: pfTs) : pfDraft);
    final savedInvestment =
        adjustedInvestment == null ? null : (invTs != null ? adjustedInvestment.copyWith(updatedAt: invTs) : adjustedInvestment);

    await _db.into(_db.transactions).insertOnConflictUpdate(savedIncome.toCompanion());
    if (savedPf != null) await _db.into(_db.transactions).insertOnConflictUpdate(savedPf.toCompanion());
    if (savedInvestment != null) await _db.into(_db.investments).insertOnConflictUpdate(savedInvestment.toCompanion());

    state = state.copyWith(
      transactions: [savedIncome, if (savedPf != null) savedPf, ...state.transactions],
      investments:
          savedInvestment != null ? _spliceById(state.investments, savedInvestment, (i) => i.id, false) : state.investments,
    );
  }

  // ── Settings / preferences ──────────────────────────────────────────────
  //
  // These stay synchronous, optimistic setters — unlike the entity mutators
  // above, a preference toggle can never corrupt financial data or double-
  // count anything, so the cloud push happens best-effort in the background
  // (consistent with how these already persisted to SharedPreferences
  // before this migration) rather than gating the UI on a round trip.

  void toggleBiometric(bool value) {
    state = state.copyWith(isBiometricEnabled: value);
    _savePref((prefs) => prefs.setBool(_kBiometricEnabled, value));
    // Deliberately device-local — never synced to the cloud.
  }

  void toggleRoundUp(bool value) {
    state = state.copyWith(isRoundUpEnabled: value);
    _savePref((prefs) => prefs.setBool(_kRoundUpEnabled, value));
    _pushSettings();
  }

  void toggleAutoBackup(bool value) {
    state = state.copyWith(isAutoBackupEnabled: value);
    _savePref((prefs) => prefs.setBool(_kAutoBackupEnabled, value));
    _pushSettings();
  }

  void setEmergencyBuffer(double amount) {
    state = state.copyWith(emergencyBuffer: amount);
    _savePref((prefs) => prefs.setDouble(_kEmergencyBuffer, amount));
    _pushSettings();
  }

  void setCurrencySymbol(String symbol) {
    state = state.copyWith(currencySymbol: symbol);
    CurrencyFormatter.updateSymbol(symbol);
    _savePref((prefs) => prefs.setString(_kCurrencySymbol, symbol));
    _pushSettings();
  }

  /// Best-effort push of the (non-biometric) preferences to the cloud
  /// `user_settings` row. Preserves whatever field-encryption key material is
  /// already stored locally so a settings change never clobbers it.
  void _pushSettings() {
    if (!hasCloudSession) return;
    _fireAndForget(() async {
      final userId = SupabaseService.client.auth.currentSession?.user.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      Future<String?> meta(String key) async =>
          (await (_db.select(_db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull())?.value;
      final row = settingsToCloudJson(
        userId,
        emergencyBuffer: prefs.getDouble(_kEmergencyBuffer) ?? 20000.0,
        currencySymbol: prefs.getString(_kCurrencySymbol) ?? '₹',
        isRoundUpEnabled: prefs.getBool(_kRoundUpEnabled) ?? false,
        isAutoBackupEnabled: prefs.getBool(_kAutoBackupEnabled) ?? false,
        updatedAt: DateTime.now(),
        secWrappedDek: await meta('sec_wrapped_dek'),
        secKekSalt: await meta('sec_kek_salt'),
        secWrappedDekRc: await meta('sec_wrapped_dek_rc'),
        secRcSalt: await meta('sec_rc_salt'),
      );
      await pushToCloud('user_settings', row);
    }, 'settings push');
  }

  Future<void> addCategory({
    required String name,
    required String type,
    required String icon,
    String colorHex = '0xFF6366F1',
    String? parentId,
  }) async {
    final draft = CategoryModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      icon: icon,
      colorHex: colorHex,
      parentId: parentId,
    );

    final serverTs = await pushToCloud('categories', draft.toCloudJson());
    final saved = serverTs == null
        ? draft
        : CategoryModel(
            id: draft.id, name: draft.name, parentId: draft.parentId, type: draft.type,
            icon: draft.icon, colorHex: draft.colorHex, updatedAt: serverTs,
          );

    await _db.into(_db.categories).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(categories: [...state.categories, saved]);
  }

  Future<void> deleteCategory(String id) async {
    final gone = state.categories.where((c) => c.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = CategoryModel(
      id: gone.first.id, name: gone.first.name, parentId: gone.first.parentId, type: gone.first.type,
      icon: gone.first.icon, colorHex: gone.first.colorHex, updatedAt: now, isDeleted: true,
    );

    await pushToCloud('categories', tombstone.toCloudJson());
    _stashDeleted('categories', gone.first.toCloudJson());

    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(categories: state.categories.where((c) => c.id != id).toList());
  }

  /// Wipes all locally persisted finance data and resets to a clean slate —
  /// used when switching to a different signed-in user on the same device.
  void clearForNewUser(String userId) {
    state = _emptyState();
    CurrencyFormatter.updateSymbol('₹'); // reset to default for the new user
    _fireAndForget(() async {
      // Drop the previous user's field-encryption key material (in-memory,
      // keystore, and the SyncMeta wrappers) before wiping the DB.
      await SecretCipherService(_db).wipe();
      await _db.wipeAllData();
      // Reseed default categories locally — the new user's `refreshFromCloud`
      // (triggered by the sign-in flow) replaces these with their own cloud
      // copy, or they become the local seed for a brand-new account.
      for (final cat in _defaultCategories()) {
        await _db.into(_db.categories).insertOnConflictUpdate(cat.toCompanion());
      }
    }, 'clearing data for new user');
  }

  Future<void> deleteTransaction(String id) async {
    // Account balances are always recomputed from transaction history, so
    // removing the row is enough for them. Credit-card / loan / investment
    // outstanding are *stored* fields that addTransaction/updateTransaction
    // mutate directly — deleting must reverse those same side effects, or a
    // deleted card charge / EMI payment / SIP silently corrupts the balance.
    final tx = state.transactions.where((t) => t.id == id).toList();
    if (tx.isEmpty) return;
    final original = tx.first;
    final now = DateTime.now();

    CreditCardModel? adjustedCard;
    if (original.creditCardId != null) {
      final i = state.creditCards.indexWhere((c) => c.id == original.creditCardId);
      // Only credit cards store an outstanding to reverse. For a debit-card
      // spend, deleting the row is enough — the linked account's balance is
      // recomputed from transaction history.
      if (i != -1 && state.creditCards[i].cardType == CardType.credit) {
        final card = state.creditCards[i];
        double outstanding = card.currentOutstanding;
        if (original.type == TransactionType.expense) {
          outstanding = (card.currentOutstanding - original.amount).clamp(0.0, double.infinity);
        } else if (original.type == TransactionType.creditCardPayment ||
            original.type == TransactionType.refund) {
          outstanding = card.currentOutstanding + original.amount;
        }
        adjustedCard = card.copyWith(currentOutstanding: outstanding, updatedAt: now);
      }
    }

    LoanModel? adjustedLoan;
    if (original.type == TransactionType.loanPayment && original.loanId != null) {
      final i = state.loans.indexWhere((l) => l.id == original.loanId);
      if (i != -1) {
        final loan = state.loans[i];
        final isScheduledEmi = (original.amount - loan.monthlyEmi).abs() < 0.01;
        adjustedLoan = LoanModel(
          id: loan.id,
          name: loan.name,
          provider: loan.provider,
          principalAmount: loan.principalAmount,
          outstandingAmount: (loan.outstandingAmount + original.amount).clamp(0.0, loan.principalAmount),
          interestRate: loan.interestRate,
          monthlyEmi: loan.monthlyEmi,
          dueDay: loan.dueDay,
          startDate: loan.startDate,
          remainingTenureMonths: isScheduledEmi ? loan.remainingTenureMonths + 1 : loan.remainingTenureMonths,
          updatedAt: now,
        );
      }
    }

    InvestmentModel? adjustedInvestment;
    if (original.type == TransactionType.investment && original.investmentId != null) {
      final i = state.investments.indexWhere((v) => v.id == original.investmentId);
      if (i != -1) {
        final inv = state.investments[i];
        adjustedInvestment = InvestmentModel(
          id: inv.id,
          name: inv.name,
          type: inv.type,
          investedAmount: (inv.investedAmount - original.amount).clamp(0.0, double.infinity),
          currentValue: (inv.currentValue - original.amount).clamp(0.0, double.infinity),
          monthlySipAmount: inv.monthlySipAmount,
          sipDay: inv.sipDay,
          updatedAt: now,
        );
      }
    }

    final tombstone = original.copyWith(isDeleted: true, updatedAt: now);
    await pushToCloud('transactions', tombstone.toCloudJson());
    if (adjustedCard != null) await pushToCloud('credit_cards', adjustedCard.toCloudJson());
    if (adjustedLoan != null) await pushToCloud('loans', adjustedLoan.toCloudJson());
    if (adjustedInvestment != null) await pushToCloud('investments', adjustedInvestment.toCloudJson());

    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    if (adjustedCard != null) await _db.into(_db.creditCards).insertOnConflictUpdate(adjustedCard.toCompanion());
    if (adjustedLoan != null) await _db.into(_db.loans).insertOnConflictUpdate(adjustedLoan.toCompanion());
    if (adjustedInvestment != null) await _db.into(_db.investments).insertOnConflictUpdate(adjustedInvestment.toCompanion());

    state = state.copyWith(
      transactions: state.transactions.where((t) => t.id != id).toList(),
      creditCards: adjustedCard != null ? _spliceById(state.creditCards, adjustedCard, (c) => c.id, false) : state.creditCards,
      loans: adjustedLoan != null ? _spliceById(state.loans, adjustedLoan, (l) => l.id, false) : state.loans,
      investments: adjustedInvestment != null
          ? _spliceById(state.investments, adjustedInvestment, (i) => i.id, false)
          : state.investments,
    );
  }

  // ── Accounts ───────────────────────────────────────────────────────────────
  Future<void> deleteAccount(String id) async {
    final gone = state.accounts.where((a) => a.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = gone.first.copyWith(isDeleted: true, updatedAt: now);

    await pushToCloud('accounts', tombstone.toCloudJson());
    _stashDeleted('accounts', gone.first.toCloudJson());

    await (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(accounts: state.accounts.where((a) => a.id != id).toList());
  }

  Future<void> updateAccount(String id, {String? name, AccountType? type, String? bank, String? accountNumberLast4, double? openingBalance, String? encAccountNumber, String? encIfsc}) async {
    final existing = state.accounts.where((a) => a.id == id).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(
      name: name, type: type, bank: bank, accountNumberLast4: accountNumberLast4,
      openingBalance: openingBalance, encAccountNumber: encAccountNumber, encIfsc: encIfsc,
    );

    final serverTs = await pushToCloud('accounts', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.accounts).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(accounts: state.accounts.map((a) => a.id == id ? saved : a).toList());
  }

  // ── Loans ──────────────────────────────────────────────────────────────────
  Future<void> deleteLoan(String id) async {
    final gone = state.loans.where((l) => l.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = LoanModel(
      id: gone.first.id, name: gone.first.name, provider: gone.first.provider,
      principalAmount: gone.first.principalAmount, outstandingAmount: gone.first.outstandingAmount,
      interestRate: gone.first.interestRate, monthlyEmi: gone.first.monthlyEmi, dueDay: gone.first.dueDay,
      startDate: gone.first.startDate, remainingTenureMonths: gone.first.remainingTenureMonths,
      updatedAt: now, isDeleted: true,
    );

    await pushToCloud('loans', tombstone.toCloudJson());
    _stashDeleted('loans', gone.first.toCloudJson());

    await (_db.update(_db.loans)..where((l) => l.id.equals(id))).write(
      LoansCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(loans: state.loans.where((l) => l.id != id).toList());
  }

  Future<void> updateLoan(String id, {String? name, String? provider, double? outstandingAmount, double? monthlyEmi, int? dueDay}) async {
    final existing = state.loans.where((l) => l.id == id).toList();
    if (existing.isEmpty) return;
    final l = existing.first;
    final draft = LoanModel(
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

    final serverTs = await pushToCloud('loans', draft.toCloudJson());
    final saved = serverTs == null
        ? draft
        : LoanModel(
            id: draft.id, name: draft.name, provider: draft.provider,
            principalAmount: draft.principalAmount, outstandingAmount: draft.outstandingAmount,
            interestRate: draft.interestRate, monthlyEmi: draft.monthlyEmi, dueDay: draft.dueDay,
            startDate: draft.startDate, remainingTenureMonths: draft.remainingTenureMonths,
            updatedAt: serverTs,
          );

    await _db.into(_db.loans).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(loans: state.loans.map((x) => x.id == id ? saved : x).toList());
  }

  // ── Budgets ────────────────────────────────────────────────────────────────
  Future<void> addBudget({required String categoryId, required double monthlyLimit, String? monthYear}) async {
    final now = DateTime.now();
    final resolvedMonthYear = monthYear ?? '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final draft = BudgetModel(
      id: _uuid.v4(),
      categoryId: categoryId,
      monthlyLimit: monthlyLimit,
      monthYear: resolvedMonthYear,
      spentAmount: 0.0,
    );

    final serverTs = await pushToCloud('budgets', draft.toCloudJson());
    final saved = serverTs == null
        ? draft
        : BudgetModel(
            id: draft.id, categoryId: draft.categoryId, monthlyLimit: draft.monthlyLimit,
            monthYear: draft.monthYear, spentAmount: draft.spentAmount, updatedAt: serverTs,
          );

    await _db.into(_db.budgets).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(budgets: [...state.budgets, saved]);
  }

  Future<void> deleteBudget(String id) async {
    final gone = state.budgets.where((b) => b.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = BudgetModel(
      id: gone.first.id, categoryId: gone.first.categoryId, monthlyLimit: gone.first.monthlyLimit,
      monthYear: gone.first.monthYear, spentAmount: gone.first.spentAmount, updatedAt: now, isDeleted: true,
    );

    await pushToCloud('budgets', tombstone.toCloudJson());
    _stashDeleted('budgets', gone.first.toCloudJson());

    await (_db.update(_db.budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(budgets: state.budgets.where((b) => b.id != id).toList());
  }

  Future<void> updateBudget(String id, {double? limitAmount, String? categoryId}) async {
    final existing = state.budgets.where((b) => b.id == id).toList();
    if (existing.isEmpty) return;
    final b = existing.first;
    final draft = BudgetModel(
      id: b.id,
      categoryId: categoryId ?? b.categoryId,
      monthlyLimit: limitAmount ?? b.monthlyLimit,
      monthYear: b.monthYear,
      spentAmount: b.spentAmount,
    );

    final serverTs = await pushToCloud('budgets', draft.toCloudJson());
    final saved = serverTs == null
        ? draft
        : BudgetModel(
            id: draft.id, categoryId: draft.categoryId, monthlyLimit: draft.monthlyLimit,
            monthYear: draft.monthYear, spentAmount: draft.spentAmount, updatedAt: serverTs,
          );

    await _db.into(_db.budgets).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(budgets: state.budgets.map((x) => x.id == id ? saved : x).toList());
  }

  // ── Recurring Payments ───────────────────────────────────────────────────────
  Future<void> addRecurringPayment({
    required String title,
    required double amount,
    required PaymentFrequency frequency,
    required DateTime nextDueDate,
    String? categoryId,
    String? accountId,
    bool isAutoPay = false,
    bool isIncome = false,
    String? companyId,
  }) async {
    final draft = RecurringPaymentModel(
      id: _uuid.v4(),
      title: title,
      amount: amount,
      frequency: frequency,
      nextDueDate: nextDueDate,
      categoryId: categoryId,
      accountId: accountId,
      isAutoPay: isAutoPay,
      isIncome: isIncome,
      companyId: companyId,
    );

    final serverTs = await pushToCloud('recurring_payments', draft.toCloudJson());
    final saved = serverTs == null ? draft : draft.copyWith(updatedAt: serverTs);

    await _db.into(_db.recurringPayments).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(recurringPayments: [...state.recurringPayments, saved]);
  }

  Future<void> updateRecurringPayment(String id, {
    String? title,
    double? amount,
    PaymentFrequency? frequency,
    DateTime? nextDueDate,
    String? categoryId,
    String? accountId,
    bool? isAutoPay,
    bool? isIncome,
    String? companyId,
  }) async {
    final existing = state.recurringPayments.where((p) => p.id == id).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(
      title: title,
      amount: amount,
      frequency: frequency,
      nextDueDate: nextDueDate,
      categoryId: categoryId,
      accountId: accountId,
      isAutoPay: isAutoPay,
      isIncome: isIncome,
      companyId: companyId,
    );

    final serverTs = await pushToCloud('recurring_payments', draft.toCloudJson());
    final saved = serverTs == null ? draft : draft.copyWith(updatedAt: serverTs);

    await _db.into(_db.recurringPayments).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(recurringPayments: state.recurringPayments.map((x) => x.id == id ? saved : x).toList());
  }

  Future<void> deleteRecurringPayment(String id) async {
    final gone = state.recurringPayments.where((p) => p.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = RecurringPaymentModel(
      id: gone.first.id, title: gone.first.title, amount: gone.first.amount, frequency: gone.first.frequency,
      nextDueDate: gone.first.nextDueDate, categoryId: gone.first.categoryId, accountId: gone.first.accountId,
      isAutoPay: gone.first.isAutoPay, updatedAt: now, isDeleted: true,
    );

    await pushToCloud('recurring_payments', tombstone.toCloudJson());
    _stashDeleted('recurring_payments', gone.first.toCloudJson());

    await (_db.update(_db.recurringPayments)..where((p) => p.id.equals(id))).write(
      RecurringPaymentsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(recurringPayments: state.recurringPayments.where((p) => p.id != id).toList());
  }

  // ── Investments ────────────────────────────────────────────────────────────
  Future<void> deleteInvestment(String id) async {
    final gone = state.investments.where((i) => i.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = InvestmentModel(
      id: gone.first.id, name: gone.first.name, type: gone.first.type,
      investedAmount: gone.first.investedAmount, currentValue: gone.first.currentValue,
      monthlySipAmount: gone.first.monthlySipAmount, sipDay: gone.first.sipDay,
      updatedAt: now, isDeleted: true,
    );

    await pushToCloud('investments', tombstone.toCloudJson());
    _stashDeleted('investments', gone.first.toCloudJson());

    await (_db.update(_db.investments)..where((i) => i.id.equals(id))).write(
      InvestmentsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)),
    );
    state = state.copyWith(investments: state.investments.where((i) => i.id != id).toList());
  }

  Future<void> updateInvestment(
    String id, {
    String? name,
    double? currentValue,
    double? investedAmount,
    double? monthlySipAmount,
    String? referenceNumber,
  }) async {
    final existing = state.investments.where((inv) => inv.id == id).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(
      name: name,
      investedAmount: investedAmount,
      currentValue: currentValue,
      monthlySipAmount: monthlySipAmount,
      referenceNumber: referenceNumber,
    );

    final serverTs = await pushToCloud('investments', draft.toCloudJson());
    final saved = serverTs == null ? draft : draft.copyWith(updatedAt: serverTs);

    await _db.into(_db.investments).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(investments: state.investments.map((x) => x.id == id ? saved : x).toList());
  }

  // ── Goals (update) ─────────────────────────────────────────────────────────
  Future<void> updateGoal(String id, {String? name, double? targetAmount, DateTime? targetDate}) async {
    final existing = state.goals.where((g) => g.id == id).toList();
    if (existing.isEmpty) return;
    final draft = existing.first.copyWith(name: name, targetAmount: targetAmount, targetDate: targetDate);

    final serverTs = await pushToCloud('goals', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.goals).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(goals: state.goals.map((g) => g.id == id ? saved : g).toList());
  }

  // ── Categories (update) ───────────────────────────────────────────────────
  Future<void> updateCategory(String id, {String? name, String? icon, String? colorHex}) async {
    final existing = state.categories.where((c) => c.id == id).toList();
    if (existing.isEmpty) return;
    final c = existing.first;
    final draft = CategoryModel(
      id: c.id, name: name ?? c.name, type: c.type,
      icon: icon ?? c.icon, colorHex: colorHex ?? c.colorHex, parentId: c.parentId,
    );

    final serverTs = await pushToCloud('categories', draft.toCloudJson());
    final saved = serverTs == null
        ? draft
        : CategoryModel(
            id: draft.id, name: draft.name, parentId: draft.parentId, type: draft.type,
            icon: draft.icon, colorHex: draft.colorHex, updatedAt: serverTs,
          );

    await _db.into(_db.categories).insertOnConflictUpdate(saved.toCompanion());
    state = state.copyWith(categories: state.categories.map((x) => x.id == id ? saved : x).toList());
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final financeNotifierProvider = StateNotifierProvider<FinanceNotifier, FinanceState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final notifier = FinanceNotifier(db);

  // Keep the card / loan / recurring payment reminders in sync with the data,
  // debounced so a burst of edits schedules once. NotificationService no-ops
  // before init() (web, `flutter test`), so this is inert there.
  Timer? debounce;
  String lastSig = '';
  notifier.onStateChanged = (s) {
    final sig = [
      for (final c in s.creditCards)
        if (!c.isDeleted) '${c.id}:${c.statementDay}:${c.dueDay}:${c.currentOutstanding}:${c.lastPaymentDate}',
      for (final l in s.loans)
        if (!l.isDeleted) 'L${l.id}:${l.dueDay}:${l.outstandingAmount}',
      for (final r in s.recurringPayments)
        if (!r.isDeleted) 'R${r.id}:${r.nextDueDate}:${r.amount}',
    ].join('|');
    if (sig == lastSig) return;
    lastSig = sig;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 600), () {
      NotificationService.schedulePaymentReminders(
        PaymentReminders.compute(s, DateTime.now()),
      );
    });
  };
  ref.onDispose(() => debounce?.cancel());
  return notifier;
});
