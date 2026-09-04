import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:aspyric/core/constants/app_constants.dart';

void main() {
  test('v1 -> v2 upgrade creates the notes table without losing existing data', () async {
    final file = File('${Directory.systemTemp.path}/migration_check_${DateTime.now().microsecondsSinceEpoch}.sqlite');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    // ── Phase 1: simulate an existing v1 install (9 tables, no `notes`) ──
    final phase1 = AppDatabase.forTesting(NativeDatabase(file));
    final m = Migrator(phase1);
    await phase1.customStatement('PRAGMA journal_mode=WAL');
    await m.createTable(phase1.accounts);
    await m.createTable(phase1.categories);
    await m.createTable(phase1.transactions);
    await m.createTable(phase1.creditCards);
    await m.createTable(phase1.loans);
    await m.createTable(phase1.budgets);
    await m.createTable(phase1.recurringPayments);
    await m.createTable(phase1.investments);
    await m.createTable(phase1.goals);
    // deliberately NOT creating `notes` — that's the v2 addition
    await phase1.customStatement('PRAGMA user_version = 1');

    final acc = AccountModel(
      id: 'acc1',
      name: 'Test Savings',
      type: AccountType.savingsAccount,
      openingBalance: 1000,
      calculatedBalance: 1000,
      createdAt: DateTime.now(),
    );
    await phase1.into(phase1.accounts).insertOnConflictUpdate(acc.toCompanion());
    await phase1.close();

    // ── Phase 2: open with the real (v2) AppDatabase against the same file ──
    final phase2 = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(phase2.close);

    final accounts = await phase2.select(phase2.accounts).get();
    expect(accounts.length, 1, reason: 'pre-existing data must survive the upgrade');
    expect(accounts.first.name, 'Test Savings');

    // This throws "no such table: notes" if the migration didn't run.
    final notes = await phase2.select(phase2.notes).get();
    expect(notes, isEmpty);

    final versionRow = await phase2.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 6);

    // v3 additions: the tombstone column is present (the sync_outbox table it
    // shipped alongside is gone again as of v6 — checked below).
    final liveAccounts =
        await (phase2.select(phase2.accounts)..where((t) => t.isDeleted.equals(false))).get();
    expect(liveAccounts.length, 1);

    // v6: sync_outbox never got created for a device jumping straight from
    // v1 to current (the outbox/pull engine is gone) — `sync_meta` stays
    // (SecretCipherService reuses it as a plain local key/value store).
    final tableNames = (await phase2.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(tableNames.contains('sync_outbox'), isFalse);
    expect(tableNames.contains('sync_meta'), isTrue);

    // v4 additions: encrypted secret columns are present and default to null.
    final cardCols = (await phase2.customSelect('PRAGMA table_info(credit_cards)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(cardCols.containsAll({'enc_card_number', 'enc_cvv', 'enc_pin', 'color_hex', 'last_payment_date', 'last_payment_amount'}), isTrue);
    final acctCols = (await phase2.customSelect('PRAGMA table_info(accounts)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(acctCols.containsAll({'enc_account_number', 'enc_ifsc'}), isTrue);
  });

  test('v5 -> v6 upgrade drops sync_outbox and prunes stale sync_meta rows, keeping the rest', () async {
    final file = File('${Directory.systemTemp.path}/migration_check_v6_${DateTime.now().microsecondsSinceEpoch}.sqlite');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    // ── Phase 1: simulate a real v5 install — sync_outbox + sync_meta exist
    // and are populated, exactly like a device that used the old sync engine.
    final phase1 = AppDatabase.forTesting(NativeDatabase(file));
    final m = Migrator(phase1);
    await phase1.customStatement('PRAGMA journal_mode=WAL');
    await m.createTable(phase1.accounts);
    await m.createTable(phase1.categories);
    await m.createTable(phase1.transactions);
    await m.createTable(phase1.creditCards);
    await m.createTable(phase1.loans);
    await m.createTable(phase1.budgets);
    await m.createTable(phase1.recurringPayments);
    await m.createTable(phase1.investments);
    await m.createTable(phase1.goals);
    await m.createTable(phase1.notes);
    await m.createTable(phase1.syncMeta);
    await phase1.customStatement('''
      CREATE TABLE sync_outbox (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        entity_table TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        op TEXT NOT NULL,
        payload TEXT NULL,
        seq INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NULL,
        next_retry_at DATETIME NOT NULL,
        dead_lettered INTEGER NOT NULL DEFAULT 0,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
    ''');
    await phase1.customStatement(
        "INSERT INTO sync_outbox (entity_table, entity_id, op, seq, next_retry_at, created_at, updated_at) "
        "VALUES ('accounts', 'acc1', 'upsert', 1, '2024-01-01', '2024-01-01', '2024-01-01')");
    await phase1.into(phase1.syncMeta).insertOnConflictUpdate(
          const SyncMetaCompanion(key: Value('watermark:accounts'), value: Value('2024-01-01')),
        );
    await phase1.into(phase1.syncMeta).insertOnConflictUpdate(
          const SyncMetaCompanion(key: Value('sec_wrapped_dek'), value: Value('keep-me-ciphertext')),
        );
    await phase1.customStatement('PRAGMA user_version = 5');
    await phase1.close();

    // ── Phase 2: open with the real (v6) AppDatabase against the same file ──
    final phase2 = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(phase2.close);

    final tableNames = (await phase2.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(tableNames.contains('sync_outbox'), isFalse, reason: 'sync_outbox must be dropped on upgrade');
    expect(tableNames.contains('sync_meta'), isTrue, reason: 'sync_meta must survive — SecretCipherService reuses it');

    final metaKeys = (await phase2.select(phase2.syncMeta).get()).map((r) => r.key).toSet();
    expect(metaKeys.contains('watermark:accounts'), isFalse, reason: 'stale sync-only rows must be pruned');
    expect(metaKeys.contains('sec_wrapped_dek'), isTrue, reason: 'encryption key material must survive untouched');

    final row = await (phase2.select(phase2.syncMeta)..where((t) => t.key.equals('sec_wrapped_dek'))).getSingle();
    expect(row.value, 'keep-me-ciphertext');
  });
}
