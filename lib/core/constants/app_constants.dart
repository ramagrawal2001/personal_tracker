enum AccountType {
  bankAccount,
  cash,
  savingsAccount,
  currentAccount,
  wallet,
  fd,
  rd,
  investmentAccount,
  otherAsset;

  String get displayName {
    switch (this) {
      case AccountType.bankAccount:
        return 'Bank Account';
      case AccountType.cash:
        return 'Cash';
      case AccountType.savingsAccount:
        return 'Savings Account';
      case AccountType.currentAccount:
        return 'Current Account';
      case AccountType.wallet:
        return 'Digital Wallet';
      case AccountType.fd:
        return 'Fixed Deposit (FD)';
      case AccountType.rd:
        return 'Recurring Deposit (RD)';
      case AccountType.investmentAccount:
        return 'Investment Account';
      case AccountType.otherAsset:
        return 'Other Asset';
    }
  }
}

enum TransactionType {
  income,
  expense,
  transfer,
  creditCardPayment,
  loanPayment,
  investment,
  refund,
  adjustment;

  String get displayName {
    switch (this) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.creditCardPayment:
        return 'Credit Card Payment';
      case TransactionType.loanPayment:
        return 'Loan Payment';
      case TransactionType.investment:
        return 'Investment';
      case TransactionType.refund:
        return 'Refund';
      case TransactionType.adjustment:
        return 'Balance Adjustment';
    }
  }
}

enum PaymentFrequency {
  daily,
  weekly,
  monthly,
  quarterly,
  yearly;

  String get displayName {
    switch (this) {
      case PaymentFrequency.daily:
        return 'Daily';
      case PaymentFrequency.weekly:
        return 'Weekly';
      case PaymentFrequency.monthly:
        return 'Monthly';
      case PaymentFrequency.quarterly:
        return 'Quarterly';
      case PaymentFrequency.yearly:
        return 'Yearly';
    }
  }
}
