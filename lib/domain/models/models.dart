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
  });

  AccountModel copyWith({
    String? name,
    AccountType? type,
    String? bank,
    String? accountNumberLast4,
    double? openingBalance,
    double? calculatedBalance,
    bool? isActive,
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

  CategoryModel({
    required this.id,
    required this.name,
    this.parentId,
    required this.type,
    required this.icon,
    this.colorHex = '0xFF6366F1',
  });
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
  final SyncStatus syncStatus;
  final DateTime createdAt;

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
    this.syncStatus = SyncStatus.synced,
    required this.createdAt,
  });

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
    SyncStatus? syncStatus,
    DateTime? createdAt,
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
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
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
  final bool isVirtual;
  final String? notes;          // PIN hint, portal URL, etc.

  // Credit-card-specific fields (only relevant for CardType.credit)
  final double creditLimit;
  final double currentOutstanding;
  final int statementDay;
  final int dueDay;
  final String? linkedAccountId;

  // Prepaid / Forex balance
  final double? balance;        // Current balance (prepaid / forex cards)
  final String? currency;       // For forex cards (USD, EUR, etc.)

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
    this.isVirtual = false,
    this.notes,
    this.creditLimit = 0,
    this.currentOutstanding = 0,
    this.statementDay = 1,
    this.dueDay = 15,
    this.linkedAccountId,
    this.balance,
    this.currency,
  });

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
    bool? isVirtual,
    String? notes,
    double? creditLimit,
    double? currentOutstanding,
    int? statementDay,
    int? dueDay,
    String? linkedAccountId,
    double? balance,
    String? currency,
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
      isVirtual: isVirtual ?? this.isVirtual,
      notes: notes ?? this.notes,
      creditLimit: creditLimit ?? this.creditLimit,
      currentOutstanding: currentOutstanding ?? this.currentOutstanding,
      statementDay: statementDay ?? this.statementDay,
      dueDay: dueDay ?? this.dueDay,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
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
  });
}

class BudgetModel {
  final String id;
  final String categoryId;
  final double monthlyLimit;
  final String monthYear; // e.g., '2026-08'
  final double spentAmount;

  double get remaining => monthlyLimit - spentAmount;
  double get percentage => monthlyLimit > 0 ? (spentAmount / monthlyLimit).clamp(0.0, 1.0) : 0.0;

  BudgetModel({
    required this.id,
    required this.categoryId,
    required this.monthlyLimit,
    required this.monthYear,
    required this.spentAmount,
  });
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

  RecurringPaymentModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.frequency,
    required this.nextDueDate,
    this.categoryId,
    this.accountId,
    this.isAutoPay = false,
  });
}

class InvestmentModel {
  final String id;
  final String name;
  final InvestmentType type;
  final double investedAmount;
  final double currentValue;
  final double monthlySipAmount;
  final int sipDay;

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
  });
}

class GoalModel {
  final String id;
  final String name;
  final double targetAmount;
  final double currentSavedAmount;
  final DateTime? targetDate;
  final String icon;
  final String colorHex;

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
  });

  GoalModel copyWith({
    String? id,
    String? name,
    double? targetAmount,
    double? currentSavedAmount,
    DateTime? targetDate,
    String? icon,
    String? colorHex,
  }) {
    return GoalModel(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentSavedAmount: currentSavedAmount ?? this.currentSavedAmount,
      targetDate: targetDate ?? this.targetDate,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}



