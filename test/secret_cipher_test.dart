import 'dart:convert';
import 'dart:typed_data';

import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/services/secret_cipher_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envelope-encryption model:
///   * DEK  — random 32-byte data key, used directly for AES-256-GCM field
///            encryption (fresh random 12-byte IV, `base64(iv):base64(ct||tag)`).
///   * KEK  — PBKDF2-HMAC-SHA256(secret, salt, 120 000) over the login password
///            or the recovery code; wraps the DEK.
/// The operator only ever sees the wrapped DEK (+ salt) — useless without the
/// user's password or recovery code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppDatabase newDb() => AppDatabase.forTesting(NativeDatabase.memory());

  const wrapperKeys = [
    'sec_wrapped_dek',
    'sec_kek_salt',
    'sec_wrapped_dek_rc',
    'sec_rc_salt',
  ];

  Future<Map<String, String>> dumpMeta(AppDatabase db, List<String> keys) async {
    final out = <String, String>{};
    for (final k in keys) {
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
    // Reset the process-global DEK cache between cases.
    await SecretCipherService.clearCachedDek();
  });

  test('onLogin provisions a DEK and encrypt -> decrypt round-trips', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);

    await svc.onLogin('user-1', 'correct horse battery staple');
    expect(svc.isReady, isTrue);

    const secret = '4111111111111111';
    final blob = svc.encryptField(secret);
    expect(blob, isNot(contains(secret)));
    expect(svc.decryptField(blob), secret);
  });

  test('two encryptField calls on the same input yield different blobs (random IV)', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);
    await svc.onLogin('user-1', 'pw-123456');

    final a = svc.encryptField('123');
    final b = svc.encryptField('123');
    expect(a, isNot(equals(b)));
    expect(svc.decryptField(a), '123');
    expect(svc.decryptField(b), '123');
  });

  test('a byte-flipped blob fails authentication and decrypts to null', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);
    await svc.onLogin('user-1', 'pw-123456');

    final blob = svc.encryptField('987654');
    final parts = blob.split(':');
    final ctBytes = Uint8List.fromList(base64Decode(parts[1]));
    ctBytes[0] ^= 0xFF; // flip the first ciphertext byte
    final flipped = '${parts[0]}:${base64Encode(ctBytes)}';
    expect(svc.decryptField(flipped), isNull);
  });

  test('wipe() forgets the DEK so existing blobs no longer decrypt', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);
    await svc.onLogin('user-1', 'pw-123456');
    final blob = svc.encryptField('sensitive');

    await svc.wipe();
    expect(svc.isReady, isFalse);
    expect(svc.decryptField(blob), isNull);
  });

  test('fresh device + wrong password cannot unwrap the DEK', () async {
    final db1 = newDb();
    addTearDown(db1.close);
    final svc1 = SecretCipherService(db1);
    await svc1.onLogin('user-1', 'right-password-1');
    final wrappers = await dumpMeta(db1, wrapperKeys);
    expect(wrappers['sec_wrapped_dek'], isNotNull);

    // New device: only the operator-visible wrappers travel via the cloud.
    await SecretCipherService.clearCachedDek();
    final db2 = newDb();
    addTearDown(db2.close);
    await loadMeta(db2, wrappers);
    final svc2 = SecretCipherService(db2);

    await svc2.onLogin('user-1', 'WRONG-password');
    expect(svc2.isReady, isFalse, reason: 'wrong password must not unlock');
    expect(await svc2.needsManualRecovery(), isTrue);
  });

  test('in-app password change: DEK unchanged, wrapped copy rewritten, decrypt still works', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);
    await svc.onLogin('user-1', 'old-password-1');
    final blob = svc.encryptField('card-number');
    final before = await dumpMeta(db, wrapperKeys);

    final ok = await svc.rewrapForPasswordChange('user-1', 'new-password-2');
    expect(ok, isTrue);
    expect(svc.decryptField(blob), 'card-number', reason: 'same DEK survives the change');

    final after = await dumpMeta(db, wrapperKeys);
    expect(after['sec_wrapped_dek'], isNot(equals(before['sec_wrapped_dek'])));
    expect(after['sec_kek_salt'], isNot(equals(before['sec_kek_salt'])));
  });

  test('email reset with the device still enrolled: next login auto re-wraps, no loss', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);
    await svc.onLogin('user-1', 'original-pw');
    final blob = svc.encryptField('ifsc-code');
    final before = await dumpMeta(db, wrapperKeys);

    // Device keystore still holds the DEK -> onLogin with the new password just
    // refreshes the wrapper.
    await svc.onLogin('user-1', 'password-after-reset');
    expect(svc.isReady, isTrue);
    expect(svc.decryptField(blob), 'ifsc-code');
    final after = await dumpMeta(db, wrapperKeys);
    expect(after['sec_wrapped_dek'], isNot(equals(before['sec_wrapped_dek'])));
  });

  test('recovery-code unwrap: fresh device after a reset with the old password lost', () async {
    final db1 = newDb();
    addTearDown(db1.close);
    final svc1 = SecretCipherService(db1);
    await svc1.onLogin('user-1', 'forgotten-pw');
    final blob = svc1.encryptField('9876543210');
    final code = await svc1.takeRecoveryCodeForOneTimeDisplay();
    expect(code, isNotNull);
    final wrappers = await dumpMeta(db1, wrapperKeys);

    await SecretCipherService.clearCachedDek();
    final db2 = newDb();
    addTearDown(db2.close);
    await loadMeta(db2, wrappers);
    final svc2 = SecretCipherService(db2);

    // New password won't open the password wrapper...
    await svc2.onLogin('user-1', 'brand-new-pw');
    expect(svc2.isReady, isFalse);

    // ...but the recovery code will, and it re-wraps under the new password.
    final ok = await svc2.restoreWithRecoveryCode('user-1', code!, 'brand-new-pw');
    expect(ok, isTrue);
    expect(svc2.isReady, isTrue);
    expect(svc2.decryptField(blob), '9876543210');
  });

  test('triple loss (no device DEK, wrong password, wrong recovery code) stays unrecoverable', () async {
    final db1 = newDb();
    addTearDown(db1.close);
    final svc1 = SecretCipherService(db1);
    await svc1.onLogin('user-1', 'lost-pw');
    final blob = svc1.encryptField('secret');
    final wrappers = await dumpMeta(db1, wrapperKeys);

    await SecretCipherService.clearCachedDek();
    final db2 = newDb();
    addTearDown(db2.close);
    await loadMeta(db2, wrappers);
    final svc2 = SecretCipherService(db2);

    await svc2.onLogin('user-1', 'guess-1');
    expect(svc2.isReady, isFalse);
    final ok = await svc2.restoreWithRecoveryCode('user-1', 'AAAA-BBBB-CCCC-DDDD', 'guess-1');
    expect(ok, isFalse);
    expect(svc2.isReady, isFalse);
    expect(svc2.decryptField(blob), isNull);
  });

  test('demo/bypass account gets a working device-only DEK', () async {
    final db = newDb();
    addTearDown(db.close);
    final svc = SecretCipherService(db);
    await svc.onLogin('demo_1', 'Aspyric@123', isDemo: true);
    expect(svc.isReady, isTrue);
    final blob = svc.encryptField('demo-secret');
    expect(svc.decryptField(blob), 'demo-secret');
  });
}
