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
    expect(versionRow.data['user_version'], 4);

    // v3 additions: the sync tables exist and the tombstone column is present.
    final outbox = await phase2.select(phase2.syncOutbox).get();
    expect(outbox, isEmpty);
    final liveAccounts =
        await (phase2.select(phase2.accounts)..where((t) => t.isDeleted.equals(false))).get();
    expect(liveAccounts.length, 1);

    // v4 additions: encrypted secret columns are present and default to null.
    final cardCols = (await phase2.customSelect('PRAGMA table_info(credit_cards)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(cardCols.containsAll({'enc_card_number', 'enc_cvv', 'enc_pin', 'color_hex'}), isTrue);
    final acctCols = (await phase2.customSelect('PRAGMA table_info(accounts)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(acctCols.containsAll({'enc_account_number', 'enc_ifsc'}), isTrue);
  });
}
