import 'package:drift/drift.dart';

@DataClassName('AccountEntry')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // AccountType enum name
  TextColumn get bank => text().nullable()();
  TextColumn get accountNumberLast4 => text().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryEntry')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get type => text()(); // 'income' or 'expense'
  TextColumn get icon => text()();
  TextColumn get colorHex => text().withDefault(const Constant('0xFF6366F1'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TransactionEntry')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get toAccountId => text().nullable()();
  TextColumn get type => text()(); // TransactionType enum name
  RealColumn get amount => real()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get merchant => text().nullable()();
  DateTimeColumn get date => dateTime()();
  TextColumn get description => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get tags => text().nullable()();
  TextColumn get creditCardId => text().nullable()();
  TextColumn get loanId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CreditCardEntry')
class CreditCards extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get bank => text()();
  TextColumn get last4 => text()();
  RealColumn get creditLimit => real()();
  IntColumn get statementDay => integer()();
  IntColumn get dueDay => integer()();
  TextColumn get linkedAccountId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LoanEntry')
class Loans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get provider => text()();
  RealColumn get principalAmount => real()();
  RealColumn get outstandingAmount => real()();
  RealColumn get interestRate => real()();
  RealColumn get monthlyEmi => real()();
  IntColumn get dueDay => integer()();
  DateTimeColumn get startDate => dateTime()();
  IntColumn get remainingTenureMonths => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetEntry')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  RealColumn get monthlyLimit => real()();
  TextColumn get monthYear => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RecurringPaymentEntry')
class RecurringPayments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  RealColumn get amount => real()();
  TextColumn get frequency => text()(); // PaymentFrequency enum name
  DateTimeColumn get nextDueDate => dateTime()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  BoolColumn get isAutoPay => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
