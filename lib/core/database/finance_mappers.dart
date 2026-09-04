import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import '../constants/app_constants.dart';
import 'app_database.dart';

/// Converts between Drift row entries and the in-memory domain models used
/// throughout the app. Kept separate from [FinanceNotifier] so the mutator
/// logic doesn't get buried under (de)serialization boilerplate.

extension AccountEntryMapper on AccountEntry {
  AccountModel toModel() {
    return AccountModel(
      id: id,
      name: name,
      type: AccountType.values.byName(type),
      bank: bank,
      accountNumberLast4: accountNumberLast4,
      openingBalance: openingBalance,
      calculatedBalance: openingBalance,
      currency: currency,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
      encAccountNumber: encAccountNumber,
      encIfsc: encIfsc,
    );
  }
}

extension AccountModelMapper on AccountModel {
  AccountsCompanion toCompanion() {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type.name),
      bank: Value(bank),
      accountNumberLast4: Value(accountNumberLast4),
      encAccountNumber: Value(encAccountNumber),
      encIfsc: Value(encIfsc),
      openingBalance: Value(openingBalance),
      currency: Value(currency),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension CategoryEntryMapper on CategoryEntry {
  CategoryModel toModel() {
    return CategoryModel(
      id: id,
      name: name,
      parentId: parentId,
      type: type,
      icon: icon,
      colorHex: colorHex,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension CategoryModelMapper on CategoryModel {
  CategoriesCompanion toCompanion() {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      parentId: Value(parentId),
      type: Value(type),
      icon: Value(icon),
      colorHex: Value(colorHex),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension TransactionEntryMapper on TransactionEntry {
  TransactionModel toModel() {
    return TransactionModel(
      id: id,
      accountId: accountId,
      toAccountId: toAccountId,
      type: TransactionType.values.byName(type),
      amount: amount,
      categoryId: categoryId,
      merchant: merchant,
      date: date,
      description: description,
      notes: notes,
      tags: tags.isEmpty ? const [] : tags.split(',').where((t) => t.isNotEmpty).toList(),
      creditCardId: creditCardId,
      loanId: loanId,
      syncStatus: SyncStatus.values.byName(syncStatus),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension TransactionModelMapper on TransactionModel {
  TransactionsCompanion toCompanion() {
    return TransactionsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      toAccountId: Value(toAccountId),
      type: Value(type.name),
      amount: Value(amount),
      categoryId: Value(categoryId),
      merchant: Value(merchant),
      date: Value(date),
      description: Value(description),
      notes: Value(notes),
      tags: Value(tags.join(',')),
      creditCardId: Value(creditCardId),
      loanId: Value(loanId),
      syncStatus: Value(syncStatus.name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension CreditCardEntryMapper on CreditCardEntry {
  CardModel toModel() {
    return CardModel(
      id: id,
      cardType: CardType.values.byName(cardType),
      name: name,
      bank: bank,
      last4: last4,
      network: CardNetwork.values.byName(network),
      cardholderName: cardholderName,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      colorPreset: CardColorPreset.values.byName(colorPreset),
      colorHex: colorHex,
      isVirtual: isVirtual,
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
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension CardModelMapper on CardModel {
  CreditCardsCompanion toCompanion() {
    return CreditCardsCompanion(
      id: Value(id),
      cardType: Value(cardType.name),
      name: Value(name),
      bank: Value(bank),
      last4: Value(last4),
      network: Value(network.name),
      cardholderName: Value(cardholderName),
      expiryMonth: Value(expiryMonth),
      expiryYear: Value(expiryYear),
      colorPreset: Value(colorPreset.name),
      colorHex: Value(colorHex),
      isVirtual: Value(isVirtual),
      notes: Value(notes),
      encCardNumber: Value(encCardNumber),
      encCvv: Value(encCvv),
      encPin: Value(encPin),
      creditLimit: Value(creditLimit),
      currentOutstanding: Value(currentOutstanding),
      statementDay: Value(statementDay),
      dueDay: Value(dueDay),
      linkedAccountId: Value(linkedAccountId),
      balance: Value(balance),
      currency: Value(currency),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension LoanEntryMapper on LoanEntry {
  LoanModel toModel() {
    return LoanModel(
      id: id,
      name: name,
      provider: provider,
      principalAmount: principalAmount,
      outstandingAmount: outstandingAmount,
      interestRate: interestRate,
      monthlyEmi: monthlyEmi,
      dueDay: dueDay,
      startDate: startDate,
      remainingTenureMonths: remainingTenureMonths,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension LoanModelMapper on LoanModel {
  LoansCompanion toCompanion() {
    return LoansCompanion(
      id: Value(id),
      name: Value(name),
      provider: Value(provider),
      principalAmount: Value(principalAmount),
      outstandingAmount: Value(outstandingAmount),
      interestRate: Value(interestRate),
      monthlyEmi: Value(monthlyEmi),
      dueDay: Value(dueDay),
      startDate: Value(startDate),
      remainingTenureMonths: Value(remainingTenureMonths),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension BudgetEntryMapper on BudgetEntry {
  BudgetModel toModel() {
    return BudgetModel(
      id: id,
      categoryId: categoryId,
      monthlyLimit: monthlyLimit,
      monthYear: monthYear,
      spentAmount: spentAmount,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension BudgetModelMapper on BudgetModel {
  BudgetsCompanion toCompanion() {
    return BudgetsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      monthlyLimit: Value(monthlyLimit),
      monthYear: Value(monthYear),
      spentAmount: Value(spentAmount),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension RecurringPaymentEntryMapper on RecurringPaymentEntry {
  RecurringPaymentModel toModel() {
    return RecurringPaymentModel(
      id: id,
      title: title,
      amount: amount,
      frequency: PaymentFrequency.values.byName(frequency),
      nextDueDate: nextDueDate,
      categoryId: categoryId,
      accountId: accountId,
      isAutoPay: isAutoPay,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension RecurringPaymentModelMapper on RecurringPaymentModel {
  RecurringPaymentsCompanion toCompanion() {
    return RecurringPaymentsCompanion(
      id: Value(id),
      title: Value(title),
      amount: Value(amount),
      frequency: Value(frequency.name),
      nextDueDate: Value(nextDueDate),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      isAutoPay: Value(isAutoPay),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension InvestmentEntryMapper on InvestmentEntry {
  InvestmentModel toModel() {
    return InvestmentModel(
      id: id,
      name: name,
      type: InvestmentType.values.byName(type),
      investedAmount: investedAmount,
      currentValue: currentValue,
      monthlySipAmount: monthlySipAmount,
      sipDay: sipDay,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension InvestmentModelMapper on InvestmentModel {
  InvestmentsCompanion toCompanion() {
    return InvestmentsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type.name),
      investedAmount: Value(investedAmount),
      currentValue: Value(currentValue),
      monthlySipAmount: Value(monthlySipAmount),
      sipDay: Value(sipDay),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}

extension GoalEntryMapper on GoalEntry {
  GoalModel toModel() {
    return GoalModel(
      id: id,
      name: name,
      targetAmount: targetAmount,
      currentSavedAmount: currentSavedAmount,
      targetDate: targetDate,
      icon: icon,
      colorHex: colorHex,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension GoalModelMapper on GoalModel {
  GoalsCompanion toCompanion() {
    return GoalsCompanion(
      id: Value(id),
      name: Value(name),
      targetAmount: Value(targetAmount),
      currentSavedAmount: Value(currentSavedAmount),
      targetDate: Value(targetDate),
      icon: Value(icon),
      colorHex: Value(colorHex),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}
