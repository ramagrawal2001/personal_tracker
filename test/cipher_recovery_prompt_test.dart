import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/secret_cipher_service.dart';
import 'package:aspyric/features/auth/presentation/cipher_recovery_prompt.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bug 10 regression: a fresh device after a password change/reset can't unwrap
/// the DEK with the current password. `SecretCipherService` must expose that as
/// a queryable `needsRecovery` state, and supplying the recovery code (via the
/// prompt) must unlock the DEK and clear the flag.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const wrapperKeys = [
    'sec_wrapped_dek',
    'sec_kek_salt',
    'sec_wrapped_dek_rc',
    'sec_rc_salt',
  ];

  Future<Map<String, String>> dumpMeta(AppDatabase db) async {
    final out = <String, String>{};
    for (final k in wrapperKeys) {
      final r = await (db.select(db.syncMeta)..where((m) => m.key.equals(k))).getSingleOrNull();
      if (r != null) out[k] = r.value;
    }
    return out;
  }

  Future<void> loadMeta(AppDatabase db, Map<String, String> meta) async {
    for (final e in meta.entries) {
      await db.into(db.syncMeta).insertOnConflictUpdate(
            SyncMetaCompanion(key: Value(e.key), value: Value(e.value)),
          );
    }
  }

  setUp(() async {
    await SecretCipherService.clearCachedDek();
  });

  test('fresh device + wrong current password -> needsRecovery; recovery code unlocks + clears it',
      () async {
    // Device 1 enrolls the user.
    final db1 = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db1.close);
    final s1 = SecretCipherService(db1);
    await s1.onLogin('user-42', 'original-pw-123');
    final blob = s1.encryptField('4111111111111111');
    final code = await s1.takeRecoveryCodeForOneTimeDisplay();
    expect(code, isNotNull);
    final wrappers = await dumpMeta(db1);

    // Device 2: only the operator-visible wrappers travel via the cloud.
    await SecretCipherService.clearCachedDek();
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db2.close);
    await loadMeta(db2, wrappers);
    final s2 = SecretCipherService(db2);

    await s2.onLogin('user-42', 'brand-new-pw-after-reset');
    expect(s2.isReady, isFalse);
    expect(SecretCipherService.needsRecovery, isTrue,
        reason: 'authenticated but DEK locked -> prompt state');

    final ok = await s2.restoreWithRecoveryCode('user-42', code!, 'brand-new-pw-after-reset');
    expect(ok, isTrue);
    expect(s2.isReady, isTrue);
    expect(SecretCipherService.needsRecovery, isFalse, reason: 'flag clears once the DEK opens');
    expect(s2.decryptField(blob), '4111111111111111');
  });

  testWidgets('the prompt renders both unlock inputs and can be skipped', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    SecretCipherService.needsRecoveryListenable.value = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => CipherRecoveryPrompt.show(context, userId: 'user-77'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock your encrypted data'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Recovery code'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Current password'), findsOneWidget);

    // Toggle to the previous-password variant and back.
    await tester.tap(find.text('I have my previous password instead'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Previous password'), findsOneWidget);

    // "Skip for now" dismisses without unlocking.
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock your encrypted data'), findsNothing);
    expect(SecretCipherService.ready, isFalse);
  });
}
