import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Accounts,
  Categories,
  Transactions,
  CreditCards,
  Loans,
  Budgets,
  RecurringPayments,
  Investments,
  Goals,
  Notes,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Used by tests to run against an in-memory or otherwise injected executor
  /// instead of a real on-disk file.
  AppDatabase.forTesting(super.executor);

  /// v2 added the `Notes` table (notes used to be in-memory only). Bumping
  /// this without a matching [migration] would leave existing installs
  /// stuck on the v1 schema forever — Drift only runs `onCreate` for a
  /// brand-new database file, so an upgrade path is required here.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(notes);
          }
        },
      );

  Future<void> wipeAllData() async {
    await transaction(() async {
      await delete(transactions).go();
      await delete(creditCards).go();
      await delete(loans).go();
      await delete(budgets).go();
      await delete(recurringPayments).go();
      await delete(investments).go();
      await delete(goals).go();
      await delete(accounts).go();
      await delete(categories).go();
      await delete(notes).go();
    });
  }

  /// Full local snapshot of every table, keyed by table name, each row
  /// serialized with Drift's own generated JSON codec. Used by
  /// [BackupService] to build the encrypted local vault export.
  Future<Map<String, dynamic>> exportSnapshot() async {
    return {
      'accounts': (await select(accounts).get()).map((e) => e.toJson()).toList(),
      'categories': (await select(categories).get()).map((e) => e.toJson()).toList(),
      'transactions': (await select(transactions).get()).map((e) => e.toJson()).toList(),
      'creditCards': (await select(creditCards).get()).map((e) => e.toJson()).toList(),
      'loans': (await select(loans).get()).map((e) => e.toJson()).toList(),
      'budgets': (await select(budgets).get()).map((e) => e.toJson()).toList(),
      'recurringPayments': (await select(recurringPayments).get()).map((e) => e.toJson()).toList(),
      'investments': (await select(investments).get()).map((e) => e.toJson()).toList(),
      'goals': (await select(goals).get()).map((e) => e.toJson()).toList(),
      'notes': (await select(notes).get()).map((e) => e.toJson()).toList(),
    };
  }

  /// Replaces all local data with the contents of a snapshot produced by
  /// [exportSnapshot]. Runs as a single transaction so a malformed snapshot
  /// can't leave the database half-restored.
  Future<void> importSnapshot(Map<String, dynamic> snapshot) async {
    List<Map<String, dynamic>> rows(String key) {
      final raw = snapshot[key];
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }

    await transaction(() async {
      await wipeAllData();
      for (final row in rows('accounts')) {
        await into(accounts).insertOnConflictUpdate(AccountEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('categories')) {
        await into(categories).insertOnConflictUpdate(CategoryEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('transactions')) {
        await into(transactions).insertOnConflictUpdate(TransactionEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('creditCards')) {
        await into(creditCards).insertOnConflictUpdate(CreditCardEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('loans')) {
        await into(loans).insertOnConflictUpdate(LoanEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('budgets')) {
        await into(budgets).insertOnConflictUpdate(BudgetEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('recurringPayments')) {
        await into(recurringPayments).insertOnConflictUpdate(RecurringPaymentEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('investments')) {
        await into(investments).insertOnConflictUpdate(InvestmentEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('goals')) {
        await into(goals).insertOnConflictUpdate(GoalEntry.fromJson(row).toCompanion(true));
      }
      for (final row in rows('notes')) {
        await into(notes).insertOnConflictUpdate(NoteEntry.fromJson(row).toCompanion(true));
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'aspyric.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
