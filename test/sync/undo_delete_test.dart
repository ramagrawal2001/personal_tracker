// Bug 2: an entity delete tombstones the row and queues a cloud delete. The
// post-delete SnackBar's "Undo" must fully reverse that within the window —
// un-tombstone locally, drop the queued cloud delete, re-enqueue an upsert.

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/providers/notes_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FinanceNotifier finance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    finance = FinanceNotifier(db, autoLoad: false);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await db.close();
  });

  Future<List<SyncOutboxEntry>> outboxFor(String table, String id) => (db.select(db.syncOutbox)
        ..where((o) => o.entityTable.equals(table) & o.entityId.equals(id)))
      .get();

  test('delete an account → pending delete row → Undo restores it and clears the delete row', () async {
    finance.addAccount(name: 'HDFC', type: AccountType.savingsAccount, openingBalance: 1000);
    final id = finance.state.accounts.single.id;
    await Future<void>.delayed(const Duration(milliseconds: 20)); // let write-through drain

    finance.deleteAccount(id);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Row is gone from state; a pending (non-dead) `delete` outbox row exists.
    expect(finance.state.accounts, isEmpty);
    final pending = await outboxFor('accounts', id);
    expect(pending.single.op, 'delete');
    expect(pending.single.deadLettered, isFalse);
    expect(finance.canUndoDelete('accounts', id), isTrue);

    // Local row is tombstoned, not hard-deleted.
    final dbRow = await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
    expect(dbRow, isNotNull);
    expect(dbRow!.isDeleted, isTrue);

    // ── Undo ──
    await finance.undoDelete('accounts', id);

    expect(finance.state.accounts.single.id, id, reason: 'account is back in state');
    final afterUndo = await outboxFor('accounts', id);
    expect(afterUndo.where((o) => o.op == 'delete'), isEmpty, reason: 'queued cloud delete is gone');
    expect(afterUndo.where((o) => o.op == 'upsert'), hasLength(1), reason: 'un-delete is queued for the cloud');
    final restored = await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
    expect(restored!.isDeleted, isFalse, reason: 'local tombstone was reversed');
  });

  test('Undo is a no-op once the window has passed', () async {
    finance.addAccount(name: 'ICICI', type: AccountType.savingsAccount, openingBalance: 500);
    final id = finance.state.accounts.single.id;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    finance.deleteAccount(id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(finance.canUndoDelete('accounts', id), isTrue);

    // A second delete of a *different* undo key does not clobber this one.
    await finance.undoDelete('accounts', id);
    expect(finance.state.accounts.single.id, id);
    // Undo again — stash already consumed → no-op, no throw.
    await finance.undoDelete('accounts', id);
    expect(finance.state.accounts.single.id, id);
  });

  test('notes: delete → Undo restores the note and drops the delete row', () async {
    final notes = NotesNotifier(db);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let _loadFromDb settle
    final note = notes.createNote().copyWith(title: 'Keep me', body: 'important');
    notes.saveNote(note);
    final id = note.id;

    // Wait until the entity row is actually persisted before deleting.
    for (var i = 0; i < 20; i++) {
      final r = await (db.select(db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();
      if (r != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    notes.deleteNote(id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notes.state.notes, isEmpty);
    expect((await outboxFor('notes', id)).single.op, 'delete');

    await notes.undoDelete(id);
    expect(notes.state.notes.single.id, id);
    expect(notes.state.notes.single.title, 'Keep me');
    expect((await outboxFor('notes', id)).where((o) => o.op == 'delete'), isEmpty);
  });
}
