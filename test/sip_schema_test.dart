import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InvestmentModel sample() => InvestmentModel(
        id: 'i1',
        name: 'Nifty 50',
        type: InvestmentType.mutualFundSip,
        investedAmount: 100000,
        currentValue: 115000,
        monthlySipAmount: 5000,
        sipDay: 7,
        autoInvestEnabled: true,
        lastAutoPostedMonth: '2026-09',
      );

  test('copyWith carries the new fields and can toggle them', () {
    final a = sample();
    expect(a.autoInvestEnabled, isTrue);
    expect(a.lastAutoPostedMonth, '2026-09');
    final b = a.copyWith(autoInvestEnabled: false, lastAutoPostedMonth: '2026-10');
    expect(b.autoInvestEnabled, isFalse);
    expect(b.lastAutoPostedMonth, '2026-10');
    // unspecified → unchanged
    expect(a.copyWith(name: 'x').autoInvestEnabled, isTrue);
  });

  test('defaults when omitted', () {
    final m = InvestmentModel(
      id: 'i2', name: 'x', type: InvestmentType.stocks,
      investedAmount: 0, currentValue: 0,
    );
    expect(m.autoInvestEnabled, isFalse);
    expect(m.lastAutoPostedMonth, isNull);
  });

  test('Drift round-trip preserves the new fields', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.investments).insertOnConflictUpdate(sample().toCompanion());
    final row = await (db.select(db.investments)..where((t) => t.id.equals('i1'))).getSingle();
    final back = row.toModel();
    expect(back.autoInvestEnabled, isTrue);
    expect(back.lastAutoPostedMonth, '2026-09');
    await db.close();
  });

  test('cloud JSON round-trip preserves the new fields', () {
    final json = sample().toCloudJson();
    expect(json['auto_invest_enabled'], true);
    expect(json['last_auto_posted_month'], '2026-09');
    final back = InvestmentCloud.fromCloud({
      ...json,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(back.autoInvestEnabled, isTrue);
    expect(back.lastAutoPostedMonth, '2026-09');
  });

  test('cloud fromCloud tolerates the columns being absent (old project)', () {
    final back = InvestmentCloud.fromCloud({
      'id': 'i3', 'name': 'x', 'type': 'other',
      'invested_amount': 0, 'current_value': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(back.autoInvestEnabled, isFalse);
    expect(back.lastAutoPostedMonth, isNull);
  });

  group('sipDebitAccountId', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('setSipDebitAccount updates state and persists', () async {
      final n = FinanceNotifier(AppDatabase.forTesting(NativeDatabase.memory()), autoLoad: false);
      expect(n.state.sipDebitAccountId, isNull);
      await n.setSipDebitAccount('acc-1');
      expect(n.state.sipDebitAccountId, 'acc-1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('finance_sip_debit_account_id'), 'acc-1');
      await n.setSipDebitAccount(null);
      expect(n.state.sipDebitAccountId, isNull);
      expect(prefs.getString('finance_sip_debit_account_id'), isNull);
    });
  });
}
