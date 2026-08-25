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
  TextColumn get tags => text().withDefault(const Constant(''))(); // comma-joined
  TextColumn get creditCardId => text().nullable()();
  TextColumn get loanId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))(); // SyncStatus enum name
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CreditCardEntry')
class CreditCards extends Table {
  TextColumn get id => text()();
  TextColumn get cardType => text().withDefault(const Constant('credit'))(); // CardType enum name
  TextColumn get name => text()();
  TextColumn get bank => text()();
  TextColumn get last4 => text()();
  TextColumn get network => text().withDefault(const Constant('visa'))(); // CardNetwork enum name
  TextColumn get cardholderName => text().withDefault(const Constant(''))();
  IntColumn get expiryMonth => integer().nullable()();
  IntColumn get expiryYear => integer().nullable()();
  TextColumn get colorPreset => text().withDefault(const Constant('midnight'))(); // CardColorPreset enum name
  BoolColumn get isVirtual => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  RealColumn get creditLimit => real().withDefault(const Constant(0))();
  RealColumn get currentOutstanding => real().withDefault(const Constant(0))();
  IntColumn get statementDay => integer().withDefault(const Constant(1))();
  IntColumn get dueDay => integer().withDefault(const Constant(15))();
  TextColumn get linkedAccountId => text().nullable()();
  RealColumn get balance => real().nullable()();
  TextColumn get currency => text().nullable()();

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
  RealColumn get spentAmount => real().withDefault(const Constant(0.0))();

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

@DataClassName('InvestmentEntry')
class Investments extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // InvestmentType enum name
  RealColumn get investedAmount => real()();
  RealColumn get currentValue => real()();
  RealColumn get monthlySipAmount => real().withDefault(const Constant(0.0))();
  IntColumn get sipDay => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GoalEntry')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentSavedAmount => real()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get icon => text().withDefault(const Constant('target'))();
  TextColumn get colorHex => text().withDefault(const Constant('0xFF6366F1'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NoteEntry')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant('defaultColor'))(); // NoteColor enum name
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isChecklist => boolean().withDefault(const Constant(false))();
  TextColumn get checklistItemsJson => text().withDefault(const Constant('[]'))();
  TextColumn get labelsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
