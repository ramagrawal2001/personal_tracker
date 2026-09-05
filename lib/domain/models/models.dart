import '../../core/constants/app_constants.dart';

class AccountModel {
  final String id;
  final String name;
  final AccountType type;
  final String? bank;
  final String? accountNumberLast4;
  final double openingBalance;
  final double calculatedBalance;
  final String currency;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  /// Sensitive bank details, AES-GCM ciphertext blobs produced by
  /// [SecretCipherService.encryptField]. Never plaintext. `accountNumberLast4`
  /// stays plaintext for display and is derived from the full number at save
  /// time.
  final String? encAccountNumber;
  final String? encIfsc;

  /// User-chosen display position (lower sorts first). Every account starts
  /// at 0 until the user actually reorders — see
  /// `FinanceNotifier.accountsWithCalculatedBalances`, which sorts by this
  /// with a stable `createdAt` tiebreak so untouched accounts keep their
  /// original relative order. Set in bulk by `FinanceNotifier.reorderAccounts`.
  final int sortOrder;

  AccountModel({
    required this.id,
    required this.name,
    required this.type,
    this.bank,
    this.accountNumberLast4,
    required this.openingBalance,
    required this.calculatedBalance,
    this.currency = 'INR',
    this.isActive = true,
    required this.createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
    this.encAccountNumber,
    this.encIfsc,
    this.sortOrder = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  AccountModel copyWith({
    String? name,
    AccountType? type,
    String? bank,
    String? accountNumberLast4,
    double? openingBalance,
    double? calculatedBalance,
    bool? isActive,
    DateTime? updatedAt,
    bool? isDeleted,
    String? encAccountNumber,
    String? encIfsc,
    int? sortOrder,
  }) {
    return AccountModel(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      bank: bank ?? this.bank,
      accountNumberLast4: accountNumberLast4 ?? this.accountNumberLast4,
      openingBalance: openingBalance ?? this.openingBalance,
      calculatedBalance: calculatedBalance ?? this.calculatedBalance,
      currency: currency,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
      encAccountNumber: encAccountNumber ?? this.encAccountNumber,
      encIfsc: encIfsc ?? this.encIfsc,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class CategoryModel {
  final String id;
  final String name;
  final String? parentId;
  final String type; // 'income' or 'expense'
  final String icon;
  final String colorHex;
  final DateTime updatedAt;
  final bool isDeleted;

  CategoryModel({
    required this.id,
    required this.name,
    this.parentId,
    required this.type,
    required this.icon,
    this.colorHex = '0xFF6366F1',
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();
}

class TransactionSplit {
  final String categoryId;
  final double amount;
  final String? note;

  TransactionSplit({
    required this.categoryId,
    required this.amount,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'amount': amount,
        'note': note,
      };

  factory TransactionSplit.fromMap(Map<String, dynamic> m) => TransactionSplit(
        categoryId: m['categoryId'] as String,
        amount: (m['amount'] as num).toDouble(),
        note: m['note'] as String?,
      );
}

enum SyncStatus {
  pending,
  synced,
  failed;

  String get displayName {
    switch (this) {
      case SyncStatus.pending:
        return 'Pending Sync (Offline)';
      case SyncStatus.synced:
        return 'Synced to Cloud';
      case SyncStatus.failed:
        return 'Sync Failed';
    }
  }
}

class TransactionModel {
  final String id;
  final String accountId;
  final String? toAccountId;
  final TransactionType type;
  final double amount;
  final String? categoryId;
  final String? merchant;
  final DateTime date;
  final String? description;
  final String? notes;
  final List<String> tags;
  final List<TransactionSplit> splits;
  final String? attachmentPath;
  final String? creditCardId;
  final String? loanId;
  final String? investmentId;
  // Which employer this income/contribution came from — set by the Log
  // Salary flow, null for every other transaction.
  final String? companyId;
  // True only for a salary-linked PF contribution leg: `accountId` is a
  // required reference (the bank the salary was credited to), not real money
  // movement — that money was diverted before it ever reached the bank, so
  // accountsWithCalculatedBalances/liquidBalanceTrend must not debit it.
  final bool isExternalToAccount;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  TransactionModel({
    required this.id,
    required this.accountId,
    this.toAccountId,
    required this.type,
    required this.amount,
    this.categoryId,
    this.merchant,
    required this.date,
    this.description,
    this.notes,
    this.tags = const [],
    this.splits = const [],
    this.attachmentPath,
    this.creditCardId,
    this.loanId,
    this.investmentId,
    this.companyId,
    this.isExternalToAccount = false,
    this.syncStatus = SyncStatus.synced,
    required this.createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  TransactionModel copyWith({
    String? id,
    String? accountId,
    String? toAccountId,
    TransactionType? type,
    double? amount,
    String? categoryId,
    String? merchant,
    DateTime? date,
    String? description,
    String? notes,
    List<String>? tags,
    List<TransactionSplit>? splits,
    String? attachmentPath,
    String? creditCardId,
    String? loanId,
    String? investmentId,
    String? companyId,
    bool? isExternalToAccount,
    SyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      toAccountId: toAccountId ?? this.toAccountId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      merchant: merchant ?? this.merchant,
      date: date ?? this.date,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      splits: splits ?? this.splits,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      creditCardId: creditCardId ?? this.creditCardId,
      loanId: loanId ?? this.loanId,
      investmentId: investmentId ?? this.investmentId,
      companyId: companyId ?? this.companyId,
      isExternalToAccount: isExternalToAccount ?? this.isExternalToAccount,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}



// ── Card Type ─────────────────────────────────────────────────────────────────
enum CardType {
  credit,
  debit,
  prepaid,
  store,
  forex;

  String get displayName {
    switch (this) {
      case CardType.credit:  return 'Credit Card';
      case CardType.debit:   return 'Debit Card';
      case CardType.prepaid: return 'Prepaid Card';
      case CardType.store:   return 'Store Card';
      case CardType.forex:   return 'Forex Card';
    }
  }

  String get emoji {
    switch (this) {
      case CardType.credit:  return '💳';
      case CardType.debit:   return '🏦';
      case CardType.prepaid: return '🎫';
      case CardType.store:   return '🛍️';
      case CardType.forex:   return '✈️';
    }
  }
}

// ── Card Network ──────────────────────────────────────────────────────────────
enum CardNetwork {
  visa,
  mastercard,
  rupay,
  amex,
  diners,
  other;

  String get displayName {
    switch (this) {
      case CardNetwork.visa:       return 'Visa';
      case CardNetwork.mastercard: return 'Mastercard';
      case CardNetwork.rupay:      return 'RuPay';
      case CardNetwork.amex:       return 'Amex';
      case CardNetwork.diners:     return 'Diners Club';
      case CardNetwork.other:      return 'Other';
    }
  }
}

// ── Card Color Preset ─────────────────────────────────────────────────────────
enum CardColorPreset {
  midnight,    // Deep navy/indigo
  gold,        // Premium gold
  rose,        // Pink gradient
  emerald,     // Green gradient
  slate,       // Dark grey
  violet,      // Purple gradient
  crimson,     // Red gradient
  ocean;       // Teal/blue gradient

  List<int> get gradientColors {
    switch (this) {
      case CardColorPreset.midnight: return [0xFF1A1A2E, 0xFF16213E, 0xFF0F3460];
      case CardColorPreset.gold:     return [0xFF8B6914, 0xFFD4A017, 0xFFF5C842];
      case CardColorPreset.rose:     return [0xFF6B1F3A, 0xFFA83261, 0xFFD45C8A];
      case CardColorPreset.emerald:  return [0xFF0D4429, 0xFF1A6B45, 0xFF28A265];
      case CardColorPreset.slate:    return [0xFF1E293B, 0xFF334155, 0xFF475569];
      case CardColorPreset.violet:   return [0xFF2D1B69, 0xFF5B21B6, 0xFF7C3AED];
      case CardColorPreset.crimson:  return [0xFF450A0A, 0xFF991B1B, 0xFFEF4444];
      case CardColorPreset.ocean:    return [0xFF0C4A6E, 0xFF075985, 0xFF0EA5E9];
    }
  }

  String get displayName {
    switch (this) {
      case CardColorPreset.midnight: return 'Midnight';
      case CardColorPreset.gold:     return 'Gold';
      case CardColorPreset.rose:     return 'Rose';
      case CardColorPreset.emerald:  return 'Emerald';
      case CardColorPreset.slate:    return 'Slate';
      case CardColorPreset.violet:   return 'Violet';
      case CardColorPreset.crimson:  return 'Crimson';
      case CardColorPreset.ocean:    return 'Ocean';
    }
  }
}

// ── CardModel — universal for all card types ──────────────────────────────────
class CardModel {
  final String id;
  final CardType cardType;
  final String name;            // e.g. "HDFC Regalia"
  final String bank;            // e.g. "HDFC Bank"
  final String last4;           // Last 4 digits
  final CardNetwork network;
  final String cardholderName;
  final int? expiryMonth;
  final int? expiryYear;
  final CardColorPreset colorPreset;
  /// Free-form card colour as `0xAARRGGBB` (same shape as
  /// [CategoryModel.colorHex]). When set it overrides [colorPreset] in the
  /// card renderers; null falls back to the preset gradient.
  final String? colorHex;
  final bool isVirtual;
  final String? notes;          // PIN hint, portal URL, etc.

  /// Sensitive card details, AES-GCM ciphertext blobs produced by
  /// [SecretCipherService.encryptField]. Never plaintext. `last4` stays
  /// plaintext for display and is derived from the full number at save time.
  final String? encCardNumber;
  final String? encCvv;
  final String? encPin;

  // Credit-card-specific fields (only relevant for CardType.credit)
  final double creditLimit;
  final double currentOutstanding;
  final int statementDay;
  final int dueDay;
  final String? linkedAccountId;

  // Prepaid / Forex balance
  final double? balance;        // Current balance (prepaid / forex cards)
  final String? currency;       // For forex cards (USD, EUR, etc.)

  final DateTime? lastPaymentDate;
  final double? lastPaymentAmount;

  final DateTime updatedAt;
  final bool isDeleted;

  double get availableLimit => creditLimit > 0 ? creditLimit - currentOutstanding : 0;
  double get utilizationPercentage => creditLimit > 0 ? (currentOutstanding / creditLimit) * 100 : 0;
  double get minimumDue => currentOutstanding * 0.05;

  bool get isExpired {
    if (expiryMonth == null || expiryYear == null) return false;
    final now = DateTime.now();
    final expiry = DateTime(expiryYear!, expiryMonth! + 1, 0);
    return now.isAfter(expiry);
  }

  bool get expiresThisYear {
    if (expiryYear == null) return false;
    return expiryYear == DateTime.now().year;
  }

  String get expiryDisplay {
    if (expiryMonth == null || expiryYear == null) return '——';
    return '${expiryMonth!.toString().padLeft(2, '0')}/${expiryYear! % 100}';
  }

  CardModel({
    required this.id,
    required this.cardType,
    required this.name,
    required this.bank,
    required this.last4,
    this.network = CardNetwork.visa,
    required this.cardholderName,
    this.expiryMonth,
    this.expiryYear,
    this.colorPreset = CardColorPreset.midnight,
    this.colorHex,
    this.isVirtual = false,
    this.notes,
    this.encCardNumber,
    this.encCvv,
    this.encPin,
    this.creditLimit = 0,
    this.currentOutstanding = 0,
    this.statementDay = 1,
    this.dueDay = 15,
    this.linkedAccountId,
    this.balance,
    this.currency,
    this.lastPaymentDate,
    this.lastPaymentAmount,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  CardModel copyWith({
    CardType? cardType,
    String? name,
    String? bank,
    String? last4,
    CardNetwork? network,
    String? cardholderName,
    int? expiryMonth,
    int? expiryYear,
    CardColorPreset? colorPreset,
    String? colorHex,
    bool? isVirtual,
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
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return CardModel(
      id: id,
      cardType: cardType ?? this.cardType,
      name: name ?? this.name,
      bank: bank ?? this.bank,
      last4: last4 ?? this.last4,
      network: network ?? this.network,
      cardholderName: cardholderName ?? this.cardholderName,
      expiryMonth: expiryMonth ?? this.expiryMonth,
      expiryYear: expiryYear ?? this.expiryYear,
      colorPreset: colorPreset ?? this.colorPreset,
      colorHex: colorHex ?? this.colorHex,
      isVirtual: isVirtual ?? this.isVirtual,
      notes: notes ?? this.notes,
      encCardNumber: encCardNumber ?? this.encCardNumber,
      encCvv: encCvv ?? this.encCvv,
      encPin: encPin ?? this.encPin,
      creditLimit: creditLimit ?? this.creditLimit,
      currentOutstanding: currentOutstanding ?? this.currentOutstanding,
      statementDay: statementDay ?? this.statementDay,
      dueDay: dueDay ?? this.dueDay,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
      lastPaymentAmount: lastPaymentAmount ?? this.lastPaymentAmount,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// Backward-compat alias so existing code using CreditCardModel still compiles
typedef CreditCardModel = CardModel;


class LoanModel {
  final String id;
  final String name;
  final String provider;
  final double principalAmount;
  final double outstandingAmount;
  final double interestRate;
  final double monthlyEmi;
  final int dueDay;
  final DateTime startDate;
  final int remainingTenureMonths;
  final DateTime updatedAt;
  final bool isDeleted;

  LoanModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.principalAmount,
    required this.outstandingAmount,
    required this.interestRate,
    required this.monthlyEmi,
    required this.dueDay,
    required this.startDate,
    required this.remainingTenureMonths,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();
}

class BudgetModel {
  final String id;
  final String categoryId;
  final double monthlyLimit;
  final String monthYear; // e.g., '2026-08'
  final double spentAmount;
  final DateTime updatedAt;
  final bool isDeleted;

  double get remaining => monthlyLimit - spentAmount;
  double get percentage => monthlyLimit > 0 ? (spentAmount / monthlyLimit).clamp(0.0, 1.0) : 0.0;

  BudgetModel({
    required this.id,
    required this.categoryId,
    required this.monthlyLimit,
    required this.monthYear,
    required this.spentAmount,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();
}

class RecurringPaymentModel {
  final String id;
  final String title;
  final double amount;
  final PaymentFrequency frequency;
  final DateTime nextDueDate;
  final String? categoryId;
  final String? accountId;
  final bool isAutoPay;
  // True for an expected incoming credit (e.g. a payday reminder) rather than
  // an outgoing bill/EMI. upcomingPaymentsTotal must skip these — an expected
  // salary credit is not a liability and must not reduce Safe-to-Spend.
  final bool isIncome;
  // Employer this reminder belongs to, when isIncome is true.
  final String? companyId;
  final DateTime updatedAt;
  final bool isDeleted;

  RecurringPaymentModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.frequency,
    required this.nextDueDate,
    this.categoryId,
    this.accountId,
    this.isAutoPay = false,
    this.isIncome = false,
    this.companyId,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  RecurringPaymentModel copyWith({
    String? id,
    String? title,
    double? amount,
    PaymentFrequency? frequency,
    DateTime? nextDueDate,
    String? categoryId,
    String? accountId,
    bool? isAutoPay,
    bool? isIncome,
    String? companyId,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return RecurringPaymentModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      frequency: frequency ?? this.frequency,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      isAutoPay: isAutoPay ?? this.isAutoPay,
      isIncome: isIncome ?? this.isIncome,
      companyId: companyId ?? this.companyId,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class InvestmentModel {
  final String id;
  final String name;
  final InvestmentType type;
  final double investedAmount;
  final double currentValue;
  final double monthlySipAmount;
  final int sipDay;
  // UAN (for EPF) or a PPF/NPS account number — plain reference data, not
  // secret enough to warrant the encrypted-card-secrets pipeline.
  final String? referenceNumber;
  final DateTime updatedAt;
  final bool isDeleted;

  double get netReturns => currentValue - investedAmount;
  double get returnsPercentage => investedAmount > 0 ? ((currentValue - investedAmount) / investedAmount) * 100 : 0.0;

  InvestmentModel({
    required this.id,
    required this.name,
    required this.type,
    required this.investedAmount,
    required this.currentValue,
    this.monthlySipAmount = 0.0,
    this.sipDay = 1,
    this.referenceNumber,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  InvestmentModel copyWith({
    String? id,
    String? name,
    InvestmentType? type,
    double? investedAmount,
    double? currentValue,
    double? monthlySipAmount,
    int? sipDay,
    String? referenceNumber,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return InvestmentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      investedAmount: investedAmount ?? this.investedAmount,
      currentValue: currentValue ?? this.currentValue,
      monthlySipAmount: monthlySipAmount ?? this.monthlySipAmount,
      sipDay: sipDay ?? this.sipDay,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class GoalModel {
  final String id;
  final String name;
  final double targetAmount;
  final double currentSavedAmount;
  final DateTime? targetDate;
  final String icon;
  final String colorHex;
  final DateTime updatedAt;
  final bool isDeleted;

  double get progressPercentage => targetAmount > 0 ? (currentSavedAmount / targetAmount).clamp(0.0, 1.0) : 0.0;
  double get remainingAmount => (targetAmount - currentSavedAmount) > 0 ? (targetAmount - currentSavedAmount) : 0.0;

  GoalModel({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentSavedAmount,
    this.targetDate,
    this.icon = 'target',
    this.colorHex = '0xFF6366F1',
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  GoalModel copyWith({
    String? id,
    String? name,
    double? targetAmount,
    double? currentSavedAmount,
    DateTime? targetDate,
    String? icon,
    String? colorHex,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return GoalModel(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentSavedAmount: currentSavedAmount ?? this.currentSavedAmount,
      targetDate: targetDate ?? this.targetDate,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// An employer. Salary transactions and payday reminders attach to one of
/// these, so switching jobs is "pick a different company" rather than
/// editing a single mutable "my employer" field.
class CompanyModel {
  final String id;
  final String name;
  final DateTime? joinedDate;
  // Exactly one company is expected to have this true at a time — enforced
  // by FinanceNotifier.setCurrentEmployer, not by the schema.
  final bool isCurrentEmployer;
  // Pre-fills the Log Salary form; both optional since a company can be
  // added before its salary details are known.
  final String? defaultBankAccountId;
  final double? defaultPfAmount;
  final DateTime updatedAt;
  final bool isDeleted;

  CompanyModel({
    required this.id,
    required this.name,
    this.joinedDate,
    this.isCurrentEmployer = false,
    this.defaultBankAccountId,
    this.defaultPfAmount,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  CompanyModel copyWith({
    String? id,
    String? name,
    DateTime? joinedDate,
    bool? isCurrentEmployer,
    String? defaultBankAccountId,
    double? defaultPfAmount,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return CompanyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      joinedDate: joinedDate ?? this.joinedDate,
      isCurrentEmployer: isCurrentEmployer ?? this.isCurrentEmployer,
      defaultBankAccountId: defaultBankAccountId ?? this.defaultBankAccountId,
      defaultPfAmount: defaultPfAmount ?? this.defaultPfAmount,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}



