import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/note_mappers.dart';
import 'package:aspyric/core/services/secret_cipher_service.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/domain/models/note_model.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Notes must be ciphertext at rest — the operator (local SQLite / Supabase)
/// can't read title / body / checklist / labels — while the logged-in user
/// sees plaintext with no prompt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  final sampleNote = NoteModel(
    id: 'n1',
    title: 'Bank locker code',
    body: 'The combination is 7-42-19, spare key with mom.',
    isChecklist: true,
    checklistItems: [
      NoteChecklistItem(id: 'c1', text: 'call the bank', isChecked: false),
      NoteChecklistItem(id: 'c2', text: 'renew FD', isChecked: true),
    ],
    labels: ['private', 'finance'],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await SecretCipherService.clearCachedDek();
    await SecretCipherService(db).onLogin('u1', 'a-strong-passphrase', isDemo: true);
  });

  tearDown(() async {
    await SecretCipherService.clearCachedDek();
    await db.close();
  });

  test('persisted Drift row holds ciphertext, not the plaintext', () async {
    await db.into(db.notes).insertOnConflictUpdate(sampleNote.toCompanion());
    final row = await db.select(db.notes).getSingle();

    expect(row.title, isNot('Bank locker code'));
    expect(row.body, isNot(contains('7-42-19')));
    expect(row.title, contains(':')); // iv:ct shape
    expect(row.checklistItemsJson, isNot(contains('call the bank')));
    expect(row.labelsJson, isNot(contains('private')));

    // ...but the DEK opens them.
    expect(SecretCipherService.decField(row.title), 'Bank locker code');
    expect(SecretCipherService.decField(row.body), contains('7-42-19'));
  });

  test('toModel() decrypts back to the exact plaintext note', () async {
    await db.into(db.notes).insertOnConflictUpdate(sampleNote.toCompanion());
    final row = await db.select(db.notes).getSingle();
    final loaded = row.toModel();

    expect(loaded.title, 'Bank locker code');
    expect(loaded.body, 'The combination is 7-42-19, spare key with mom.');
    expect(loaded.checklistItems.map((e) => e.text), ['call the bank', 'renew FD']);
    expect(loaded.checklistItems[1].isChecked, isTrue);
    expect(loaded.labels, ['private', 'finance']);
  });

  test('a legacy plaintext row still loads (no crash, shown raw)', () async {
    await db.into(db.notes).insertOnConflictUpdate(NotesCompanion.insert(
      id: 'legacy',
      title: const Value('plain old title'),
      body: const Value('plain old body'),
      checklistItemsJson: const Value('[]'),
      labelsJson: const Value('[]'),
      createdAt: DateTime(2025, 6, 1),
      updatedAt: DateTime(2025, 6, 1),
    ));
    final row = await (db.select(db.notes)..where((n) => n.id.equals('legacy'))).getSingle();
    final loaded = row.toModel();
    expect(loaded.title, 'plain old title');
    expect(loaded.body, 'plain old body');
    expect(loaded.checklistItems, isEmpty);
  });

  test('cloud json carries ciphertext; fromCloud restores plaintext', () {
    final json = sampleNote.toCloudJson();
    expect(json['title'], isNot('Bank locker code'));
    expect(json['body'].toString(), isNot(contains('7-42-19')));
    expect(json['checklist_items'].toString(), isNot(contains('call the bank')));

    final back = NoteCloud.fromCloud(json);
    expect(back.title, 'Bank locker code');
    expect(back.body, contains('7-42-19'));
    expect(back.checklistItems.map((e) => e.text), ['call the bank', 'renew FD']);
    expect(back.labels, ['private', 'finance']);
  });

  test('cipher not ready → stores plaintext (never loses data)', () async {
    await SecretCipherService.clearCachedDek();
    expect(SecretCipherService.ready, isFalse);
    expect(SecretCipherService.encField('unencrypted'), 'unencrypted');

    await db.into(db.notes).insertOnConflictUpdate(sampleNote.toCompanion());
    final row = await db.select(db.notes).getSingle();
    expect(row.title, 'Bank locker code'); // stored as-is, not lost
    expect(row.toModel().title, 'Bank locker code');
  });
}
