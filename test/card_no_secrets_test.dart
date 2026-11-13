import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cards and bank accounts keep only their last-4 digits. There is no column
/// or cloud field for a full card number, CVV, ATM PIN, full account number or
/// IFSC — encrypted or otherwise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addCard stores only last4, and no secret column exists', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notifier = FinanceNotifier(db, autoLoad: false);
    addTearDown(notifier.dispose);

    await notifier.addCard(
      cardType: CardType.credit,
      name: 'Test Card',
      bank: 'Test Bank',
      last4: '1234',
      cardholderName: 'Test Holder',
      notes: 'portal: example.com',
    );

    final row = await db.select(db.creditCards).getSingle();
    expect(row.last4, '1234');

    final cardCols = (await db.customSelect('PRAGMA table_info(credit_cards)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(cardCols.intersection({'enc_card_number', 'enc_cvv', 'enc_pin'}), isEmpty);

    final cloudJson = row.toModel().toCloudJson();
    expect(cloudJson['last4'], '1234');
    expect(cloudJson.keys.where((k) => k.startsWith('enc_')), isEmpty);
  });

  test('addAccount stores only last4, and no secret column exists', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notifier = FinanceNotifier(db, autoLoad: false);
    addTearDown(notifier.dispose);

    await notifier.addAccount(
      name: 'Savings',
      type: AccountType.savingsAccount,
      accountNumberLast4: '4321',
      openingBalance: 500,
    );

    final row = await db.select(db.accounts).getSingle();
    expect(row.accountNumberLast4, '4321');

    final acctCols = (await db.customSelect('PRAGMA table_info(accounts)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(acctCols.intersection({'enc_account_number', 'enc_ifsc'}), isEmpty);
    expect(row.toModel().toCloudJson().keys.where((k) => k.startsWith('enc_')), isEmpty);
  });
}
