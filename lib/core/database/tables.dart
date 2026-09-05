import 'package:drift/drift.dart';

@DataClassName('AccountEntry')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // AccountType enum name
  TextColumn get bank => text().nullable()();
  TextColumn get accountNumberLast4 => text().nullable()();
  // v4: sensitive bank details — AES-GCM ciphertext blobs, never plaintext.
  TextColumn get encAccountNumber => text().nullable()();
  TextColumn get encIfsc => text().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  // Sync tombstone columns (updatedAt already present above).
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  TextColumn get companyId => text().nullable()();
  BoolColumn get isExternalToAccount => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))(); // SyncStatus enum name
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  // v4: free-form card colour as 0xAARRGGBB; null → use colorPreset.
  TextColumn get colorHex => text().nullable()();
  BoolColumn get isVirtual => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  // v4: sensitive card details — AES-GCM ciphertext blobs, never plaintext.
  TextColumn get encCardNumber => text().nullable()();
  TextColumn get encCvv => text().nullable()();
  TextColumn get encPin => text().nullable()();
  RealColumn get creditLimit => real().withDefault(const Constant(0))();
  RealColumn get currentOutstanding => real().withDefault(const Constant(0))();
  IntColumn get statementDay => integer().withDefault(const Constant(1))();
  IntColumn get dueDay => integer().withDefault(const Constant(15))();
  TextColumn get linkedAccountId => text().nullable()();
  RealColumn get balance => real().nullable()();
  TextColumn get currency => text().nullable()();
  DateTimeColumn get lastPaymentDate => dateTime().nullable()();
  RealColumn get lastPaymentAmount => real().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();
  TextColumn get companyId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  TextColumn get referenceNumber => text().nullable()(); // UAN / PPF-NPS account number
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CompanyEntry')
class Companies extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get joinedDate => dateTime().nullable()();
  BoolColumn get isCurrentEmployer => boolean().withDefault(const Constant(false))();
  TextColumn get defaultBankAccountId => text().nullable()();
  RealColumn get defaultPfAmount => real().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small local key/value store. Historically also held the outbox/pull
/// bookkeeping for the (now-removed) sync engine — that usage is gone, along
/// with the `SyncOutbox` table it worked alongside (see the v6 migration in
/// `app_database.dart`, which drops `sync_outbox` and the stale sync-only
/// keys here). What remains load-bearing: `SecretCipherService` stores the
/// field-encryption key-wrapping material under it (`sec_wrapped_dek`,
/// `sec_kek_salt`, `sec_wrapped_dek_rc`, `sec_rc_salt`) — that is *not*
/// sync bookkeeping, so this table itself is kept rather than dropped.
@DataClassName('SyncMetaEntry')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
