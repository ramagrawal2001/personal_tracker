import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/secret_cipher_service.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saving a card through [FinanceNotifier] must persist only ciphertext for the
/// sensitive fields — the plaintext card number / CVV / PIN must never touch a
/// Drift column, and `last4` stays plaintext for display.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fullNumber = '4111111111111234';
  const cvv = '321';
  const pin = '4729';

  test('addCard persists AES-GCM ciphertext, never the raw number', () async {
    await SecretCipherService.clearCachedDek();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(SecretCipherService.clearCachedDek);

    final cipher = SecretCipherService(db);
    await cipher.onLogin('user-1', 'test-pass-123456');
    expect(cipher.isReady, isTrue);

    final notifier = FinanceNotifier(db, autoLoad: false);
    addTearDown(notifier.dispose);

    final encNumber = cipher.encryptField(fullNumber);
    await notifier.addCard(
      cardType: CardType.credit,
      name: 'Test Card',
      bank: 'Test Bank',
      last4: fullNumber.substring(fullNumber.length - 4),
      cardholderName: 'Test Holder',
      encCardNumber: encNumber,
      encCvv: cipher.encryptField(cvv),
      encPin: cipher.encryptField(pin),
      notes: 'portal: example.com',
    );

    final row = await db.select(db.creditCards).getSingle();

    // last4 stays plaintext for display.
    expect(row.last4, '1234');

    // The encrypted column holds exactly the ciphertext blob we produced.
    expect(row.encCardNumber, encNumber);
    expect(row.encCardNumber, isNot(fullNumber));
    expect(cipher.decryptField(row.encCardNumber), fullNumber);
    expect(cipher.decryptField(row.encCvv), cvv);
    expect(cipher.decryptField(row.encPin), pin);

    // No column anywhere contains the full plaintext number.
    for (final entry in row.toJson().entries) {
      final s = entry.value?.toString() ?? '';
      expect(s.contains(fullNumber), isFalse, reason: 'plaintext number leaked into ${entry.key}');
    }
    // The plaintext CVV / PIN only ever live inside their own encrypted blobs.
    expect(row.notes?.contains(cvv) ?? false, isFalse);
    expect(row.notes?.contains(pin) ?? false, isFalse);

    // The cloud payload built from this row is ciphertext too.
    final cloudJson = row.toModel().toCloudJson();
    expect(cloudJson['enc_card_number'], encNumber);
    expect(cloudJson.toString().contains(fullNumber), isFalse);
  });
}
