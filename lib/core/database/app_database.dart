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
  SyncOutbox,
  SyncMeta,
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(notes);
          }
          if (from < 3) {
            // Columns are added defensively: a synthetic upgrade path (see
            // test/migration_check_test.dart) may create the tables from the
            // current schema first, so an unconditional addColumn would hit
            // "duplicate column name".
            final columnCache = <String, Set<String>>{};
            Future<Set<String>> existingColumns(String table) async {
              return columnCache[table] ??= (await customSelect('PRAGMA table_info($table)').get())
                  .map((row) => row.read<String>('name'))
                  .toSet();
            }

            Future<void> addColumnIfMissing(TableInfo table, GeneratedColumn column) async {
              final cols = await existingColumns(table.actualTableName);
              if (!cols.contains(column.name)) {
                await m.addColumn(table, column);
                cols.add(column.name);
              }
            }

            // `updatedAt` for tables that did not already have it.
            await addColumnIfMissing(categories, categories.updatedAt);
            await addColumnIfMissing(transactions, transactions.updatedAt);
            await addColumnIfMissing(creditCards, creditCards.updatedAt);
            await addColumnIfMissing(loans, loans.updatedAt);
            await addColumnIfMissing(budgets, budgets.updatedAt);
            await addColumnIfMissing(recurringPayments, recurringPayments.updatedAt);
            await addColumnIfMissing(investments, investments.updatedAt);
            await addColumnIfMissing(goals, goals.updatedAt);

            // `isDeleted` / `deletedAt` tombstone columns on every entity table.
            for (final entry in <List<Object>>[
              [accounts, accounts.isDeleted, accounts.deletedAt],
              [categories, categories.isDeleted, categories.deletedAt],
              [transactions, transactions.isDeleted, transactions.deletedAt],
              [creditCards, creditCards.isDeleted, creditCards.deletedAt],
              [loans, loans.isDeleted, loans.deletedAt],
              [budgets, budgets.isDeleted, budgets.deletedAt],
              [recurringPayments, recurringPayments.isDeleted, recurringPayments.deletedAt],
              [investments, investments.isDeleted, investments.deletedAt],
              [goals, goals.isDeleted, goals.deletedAt],
              [notes, notes.isDeleted, notes.deletedAt],
            ]) {
              await addColumnIfMissing(entry[0] as TableInfo, entry[1] as GeneratedColumn);
              await addColumnIfMissing(entry[0] as TableInfo, entry[2] as GeneratedColumn);
            }

            await m.createTable(syncOutbox);
            await m.createTable(syncMeta);

            // Only `transactions` carries a `created_at` we can backfill from.
            await customStatement('UPDATE transactions SET updated_at = created_at');
          }
          if (from < 4) {
            // v4: encrypted sensitive card/bank columns + free-form card colour.
            // Added defensively (a synthetic upgrade path may have already
            // created the tables from the current schema).
            final v4Cache = <String, Set<String>>{};
            Future<Set<String>> v4Cols(String table) async {
              return v4Cache[table] ??= (await customSelect('PRAGMA table_info($table)').get())
                  .map((row) => row.read<String>('name'))
                  .toSet();
            }

            Future<void> addV4(TableInfo table, GeneratedColumn column) async {
              final cols = await v4Cols(table.actualTableName);
              if (!cols.contains(column.name)) {
                await m.addColumn(table, column);
                cols.add(column.name);
              }
            }

            await addV4(creditCards, creditCards.encCardNumber);
            await addV4(creditCards, creditCards.encCvv);
            await addV4(creditCards, creditCards.encPin);
            await addV4(creditCards, creditCards.colorHex);
            await addV4(accounts, accounts.encAccountNumber);
            await addV4(accounts, accounts.encIfsc);
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
      await delete(syncOutbox).go();
      await delete(syncMeta).go();
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
