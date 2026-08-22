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



class CreditCardModel {
  final String id;
  final String name;
  final String bank;
  final String last4;
  final double creditLimit;
  final double currentOutstanding;
  final int statementDay;
  final int dueDay;
  final String? linkedAccountId;

  double get availableLimit => creditLimit - currentOutstanding;
  double get utilizationPercentage => (currentOutstanding / creditLimit) * 100;
  double get minimumDue => currentOutstanding * 0.05; // 5% minimum due estimation

  CreditCardModel({
    required this.id,
    required this.name,
    required this.bank,
    required this.last4,
    required this.creditLimit,
    required this.currentOutstanding,
    required this.statementDay,
    required this.dueDay,
    this.linkedAccountId,
  });
}

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
  double get percentage => (spentAmount / monthlyLimit).clamp(0.0, 1.0);

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



