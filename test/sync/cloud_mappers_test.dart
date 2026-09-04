import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:aspyric/domain/models/note_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ts = DateTime(2026, 3, 14, 9, 30, 15);

  group('cloud_mappers round-trip (model -> json -> model -> json)', () {
    test('AccountModel', () {
      final m = AccountModel(
        id: 'acc-1',
        name: 'Savings',
        type: AccountType.savingsAccount,
        bank: 'HDFC',
        accountNumberLast4: '4321',
        openingBalance: 1000.5,
        calculatedBalance: 1234.75,
        currency: 'USD',
        isActive: false,
        createdAt: ts,
        updatedAt: ts,
        isDeleted: true,
        encAccountNumber: 'aXY=:Zzz111==',
        encIfsc: 'iv2=:ct2==',
      );
      final json = m.toCloudJson();
      final back = AccountCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(json['type'], 'savingsAccount');
      expect(json['is_active'], false);
      expect(json['is_deleted'], true);
      expect(json['enc_account_number'], 'aXY=:Zzz111==');
      expect(json['enc_ifsc'], 'iv2=:ct2==');
      expect((json['updated_at'] as String).endsWith('Z'), isTrue);
      expect(back.type, AccountType.savingsAccount);
      expect(back.encAccountNumber, 'aXY=:Zzz111==');
      expect(back.encIfsc, 'iv2=:ct2==');
      expect(back.updatedAt.toUtc(), ts.toUtc());
    });

    test('CategoryModel', () {
      final m = CategoryModel(
        id: 'cat_food',
        name: 'Food',
        parentId: 'root',
        type: 'expense',
        icon: 'utensils',
        colorHex: '0xFFABCDEF',
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      expect(CategoryCloud.fromCloud(json).toCloudJson(), json);
      expect(json['color_hex'], '0xFFABCDEF');
      expect(json['parent_id'], 'root');
    });

    test('TransactionModel (tags + splits jsonb, enums, nullables)', () {
      final m = TransactionModel(
        id: 'tx-1',
        accountId: 'acc-1',
        toAccountId: 'acc-2',
        type: TransactionType.transfer,
        amount: 250.0,
        categoryId: 'cat_food',
        merchant: 'Cafe',
        date: ts,
        description: 'lunch',
        notes: 'with team',
        tags: const ['work', 'reimbursable'],
        splits: [
          TransactionSplit(categoryId: 'cat_food', amount: 150, note: 'mains'),
          TransactionSplit(categoryId: 'cat_bills', amount: 100),
        ],
        attachmentPath: '/tmp/receipt.png',
        investmentId: null,
        syncStatus: SyncStatus.pending,
        createdAt: ts,
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      final back = TransactionCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(json['tags'], ['work', 'reimbursable']);
      expect((json['splits'] as List).first, {'categoryId': 'cat_food', 'amount': 150, 'note': 'mains'});
      expect(back.type, TransactionType.transfer);
      expect(back.syncStatus, SyncStatus.pending);
      expect(back.splits.length, 2);
      expect(back.splits[1].note, isNull);
      expect(back.date.toUtc(), ts.toUtc());
    });

    test('CardModel', () {
      final m = CardModel(
        id: 'card-1',
        cardType: CardType.forex,
        name: 'Travel',
        bank: 'ICICI',
        last4: '9999',
        network: CardNetwork.amex,
        cardholderName: 'A B',
        expiryMonth: 11,
        expiryYear: 2030,
        colorPreset: CardColorPreset.ocean,
        colorHex: '0xFF3B82F6',
        isVirtual: true,
        notes: 'pin hint',
        encCardNumber: 'ivA=:ctA==',
        encCvv: 'ivB=:ctB==',
        encPin: 'ivC=:ctC==',
        creditLimit: 50000,
        currentOutstanding: 1200.25,
        statementDay: 5,
        dueDay: 20,
        linkedAccountId: 'acc-1',
        balance: 300.0,
        currency: 'EUR',
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      final back = CardCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(back.cardType, CardType.forex);
      expect(back.network, CardNetwork.amex);
      expect(back.colorPreset, CardColorPreset.ocean);
      expect(json['color_hex'], '0xFF3B82F6');
      expect(json['enc_card_number'], 'ivA=:ctA==');
      expect(json['enc_cvv'], 'ivB=:ctB==');
      expect(json['enc_pin'], 'ivC=:ctC==');
      expect(back.colorHex, '0xFF3B82F6');
      expect(back.encCardNumber, 'ivA=:ctA==');
      expect(back.encCvv, 'ivB=:ctB==');
      expect(back.encPin, 'ivC=:ctC==');
      expect(back.balance, 300.0);
    });

    test('LoanModel', () {
      final m = LoanModel(
        id: 'loan-1',
        name: 'Car',
        provider: 'SBI',
        principalAmount: 800000,
        outstandingAmount: 650000,
        interestRate: 8.5,
        monthlyEmi: 15000,
        dueDay: 7,
        startDate: ts,
        remainingTenureMonths: 42,
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      final back = LoanCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(back.startDate.toUtc(), ts.toUtc());
      expect(back.remainingTenureMonths, 42);
    });

    test('BudgetModel', () {
      final m = BudgetModel(
        id: 'b-1',
        categoryId: 'cat_food',
        monthlyLimit: 12000,
        monthYear: '2026-03',
        spentAmount: 3400.5,
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      expect(BudgetCloud.fromCloud(json).toCloudJson(), json);
    });

    test('RecurringPaymentModel', () {
      final m = RecurringPaymentModel(
        id: 'r-1',
        title: 'Netflix',
        amount: 649,
        frequency: PaymentFrequency.monthly,
        nextDueDate: ts,
        categoryId: 'cat_bills',
        accountId: 'acc-1',
        isAutoPay: true,
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      final back = RecurringPaymentCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(back.frequency, PaymentFrequency.monthly);
      expect(back.isAutoPay, true);
    });

    test('InvestmentModel', () {
      final m = InvestmentModel(
        id: 'i-1',
        name: 'Index Fund',
        type: InvestmentType.mutualFundSip,
        investedAmount: 100000,
        currentValue: 121000,
        monthlySipAmount: 5000,
        sipDay: 3,
        updatedAt: ts,
      );
      final json = m.toCloudJson();
      final back = InvestmentCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(back.type, InvestmentType.mutualFundSip);
    });

    test('GoalModel (nullable target_date both ways)', () {
      final withDate = GoalModel(
        id: 'g-1',
        name: 'Trip',
        targetAmount: 200000,
        currentSavedAmount: 50000,
        targetDate: ts,
        icon: 'plane',
        colorHex: '0xFF112233',
        updatedAt: ts,
      );
      expect(GoalCloud.fromCloud(withDate.toCloudJson()).toCloudJson(), withDate.toCloudJson());

      final noDate = GoalModel(
        id: 'g-2',
        name: 'Fund',
        targetAmount: 100,
        currentSavedAmount: 0,
        updatedAt: ts,
      );
      final json = noDate.toCloudJson();
      expect(json['target_date'], isNull);
      expect(GoalCloud.fromCloud(json).targetDate, isNull);
    });

    test('NoteModel (checklist + labels jsonb)', () {
      final m = NoteModel(
        id: 'n-1',
        title: 'Groceries',
        body: 'body',
        color: NoteColor.teal,
        isPinned: true,
        isArchived: false,
        isChecklist: true,
        checklistItems: const [
          NoteChecklistItem(id: 'c1', text: 'Milk', isChecked: true),
          NoteChecklistItem(id: 'c2', text: 'Eggs'),
        ],
        labels: const ['home', 'weekly'],
        createdAt: ts,
        updatedAt: ts,
        isDeleted: true,
      );
      final json = m.toCloudJson();
      final back = NoteCloud.fromCloud(json);
      expect(back.toCloudJson(), json);
      expect(json['color'], 'teal');
      // title / body / labels / checklist_items ship as (encrypted) strings —
      // never the readable plaintext.
      expect(json['labels'], isA<String>());
      expect(json['checklist_items'], isA<String>());
      expect(json['body'], isNot('body containing readable text'));
      // ...and the round-trip restores the exact plaintext note.
      expect(back.title, 'Groceries');
      expect(back.labels, ['home', 'weekly']);
      expect(back.checklistItems.length, 2);
      expect(back.checklistItems.first.text, 'Milk');
      expect(back.checklistItems.first.isChecked, true);
      expect(back.isDeleted, true);
    });

    test('settingsToCloudJson / CloudSettings.fromCloud', () {
      final json = settingsToCloudJson(
        'user-9',
        emergencyBuffer: 35000,
        currencySymbol: r'$',
        isRoundUpEnabled: true,
        isAutoBackupEnabled: false,
        updatedAt: ts,
      );
      expect(json['user_id'], 'user-9');
      expect(json.containsKey('is_biometric_enabled'), isFalse);
      final s = CloudSettings.fromCloud(json);
      expect(s.emergencyBuffer, 35000);
      expect(s.currencySymbol, r'$');
      expect(s.isRoundUpEnabled, true);
      expect(s.isAutoBackupEnabled, false);
      expect(s.updatedAt.toUtc(), ts.toUtc());
    });
  });
}
