import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/note_mappers.dart';
import 'package:aspyric/core/providers/notes_provider.dart';
import 'package:aspyric/core/services/secret_cipher_service.dart';
import 'package:aspyric/domain/models/note_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bug 4 regression: on a session-restore cold start the notifiers can map
/// encrypted rows BEFORE `SecretCipherService.restoreFromCache()` has populated
/// the in-memory DEK (the keystore read is async). Without a reload trigger the
/// UI shows ciphertext until something else forces a re-read.
///
/// `SecretCipherService.readyListenable` flips the moment the DEK arrives and
/// `NotesNotifier` / `FinanceNotifier` listen to it and re-read from Drift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notes mapped before the DEK is ready re-decrypt once it arrives', () async {
    await SecretCipherService.clearCachedDek();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(SecretCipherService.clearCachedDek);

    // Provision a DEK and persist ONE encrypted note row, then drop the DEK to
    // simulate the next cold start where the keystore read has not finished.
    final cipher = SecretCipherService(db);
    await cipher.onLogin('u1', 'pw-12345678');
    expect(SecretCipherService.ready, isTrue);

    final note = NoteModel(
      id: 'n1',
      title: 'Locker code',
      body: '7-42-19',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );
    await db.into(db.notes).insertOnConflictUpdate(note.toCompanion());
    final storedRow = await db.select(db.notes).getSingle();
    expect(storedRow.title, isNot('Locker code'), reason: 'ciphertext at rest');

    await SecretCipherService.clearCachedDek();
    expect(SecretCipherService.ready, isFalse);

    // Cold start: the notifier loads while the DEK is still absent.
    final notifier = NotesNotifier(db);
    addTearDown(notifier.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(notifier.state.notes, hasLength(1));
    expect(notifier.state.notes.single.title, isNot('Locker code'),
        reason: 'without a DEK the note maps to ciphertext');

    // The DEK becomes available (any path). The notifier must re-read + decrypt.
    await cipher.onLogin('u1', 'pw-12345678');
    expect(SecretCipherService.ready, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(notifier.state.notes.single.title, 'Locker code');
    expect(notifier.state.notes.single.body, '7-42-19');
  });

  test('a reload when the DEK was already ready on first load is a no-op', () async {
    await SecretCipherService.clearCachedDek();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(SecretCipherService.clearCachedDek);

    final cipher = SecretCipherService(db);
    await cipher.onLogin('u1', 'pw-12345678');

    final notifier = NotesNotifier(db);
    addTearDown(notifier.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // DEK was ready on first load -> the readyListenable listener must not
    // re-trigger a load loop. A second onLogin (DEK already cached) is a no-op
    // and state stays consistent.
    await cipher.onLogin('u1', 'pw-12345678');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(notifier.state.notes, isEmpty);
  });
}
