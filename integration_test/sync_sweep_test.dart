// End-to-end sync sweep: boots the real AspyricApp with the cloud gateway
// swapped for an in-memory fake, signs in, creates one of every entity + a
// note + a settings change through the real notifiers, and asserts every
// mutation reached the "cloud". Then it pushes remote changes back through the
// realtime stream and asserts the live app state converges, and that a delete
// propagates as a tombstone.
//
// Run:  flutter test integration_test/sync_sweep_test.dart -d macos

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';

import 'package:aspyric/main.dart';
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/providers/notes_provider.dart';
import 'package:aspyric/core/sync/cloud_gateway.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/domain/models/models.dart';

import '../test/sync/fake_cloud_gateway.dart';
import '../test/support/test_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // No network in the test sandbox — fall back to the platform font instead of
  // fetching Inter from fonts.gstatic.com (which otherwise throws post-test).
  bootstrapTestEnv();

  Future<void> settle(WidgetTester t, {int frames = 25}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpUntil(WidgetTester t, bool Function() cond, {int frames = 200}) async {
    for (var i = 0; i < frames; i++) {
      if (cond()) return;
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  bool present(String s) => find.text(s).evaluate().isNotEmpty;

  testWidgets('every local mutation reaches the cloud; realtime + delete converge back',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fake = FakeCloudGateway();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(fake.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cloudGatewayProvider.overrideWithValue(fake),
        ],
        child: const AspyricApp(),
      ),
    );
    await pumpUntil(tester, () => present('Sign In to Aspyric'));

    // Demo bypass account — still produces a non-null AuthState.user, which is
    // what syncServiceProvider's auth listener keys on.
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), 'test@aspyric.app');
    await tester.enterText(f.at(1), 'Aspyric@123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await pumpUntil(tester, () => present('Dashboard'));
    await settle(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(AspyricApp)));
    final finance = container.read(financeNotifierProvider.notifier);
    final notes = container.read(notesProvider.notifier);
    final sync = container.read(syncServiceProvider);
    // Stop the periodic drain timer before the test ends, or the binding trips
    // its "no pending frame" assertion on a live device.
    addTearDown(sync.stop);

    // ── backfill: first start() seeds every existing local row (default
    //    categories) + a user_settings row ─────────────────────────────────
    await sync.flushNow();
    await settle(tester);
    expect(fake.rowCount('user_settings'), 1, reason: 'settings backfilled');
    expect(fake.rowCount('categories'), greaterThan(0), reason: 'default categories backfilled');

    // ── create one of every entity + a note + a settings change ───────────
    finance.addAccount(name: 'E2E Checking', type: AccountType.savingsAccount, openingBalance: 1000);
    final accId = container.read(financeNotifierProvider).accounts.last.id;
    final catId = container.read(financeNotifierProvider).categories.first.id;

    finance.addTransaction(
      accountId: accId,
      type: TransactionType.expense,
      amount: 42.5,
      categoryId: catId,
      merchant: 'E2E Store',
      date: DateTime.now(),
    );
    finance.addCategory(name: 'E2E Cat', type: 'expense', icon: 'tag');
    finance.addCreditCard(
      name: 'E2E Card', bank: 'E2E Bank', last4: '4242',
      creditLimit: 5000, statementDay: 1, dueDay: 15,
    );
    finance.addLoan(
      name: 'E2E Loan', provider: 'E2E Fin', principalAmount: 20000,
      interestRate: 9.5, monthlyEmi: 1800, dueDay: 5, tenureMonths: 12,
    );
    finance.addBudget(categoryId: catId, monthlyLimit: 3000);
    finance.addInvestment(
      name: 'E2E SIP', type: InvestmentType.stocks, investedAmount: 10000, currentValue: 11000,
    );
    finance.addGoal(name: 'E2E Goal', targetAmount: 50000, currentSavedAmount: 5000);
    finance.addRecurringPayment(
      title: 'E2E Rent', amount: 15000,
      frequency: PaymentFrequency.monthly, nextDueDate: DateTime.now().add(const Duration(days: 3)),
    );

    final note = notes.createNote();
    notes.saveNote(note.copyWith(title: 'E2E Note', body: 'hello cloud'));

    finance.setCurrencySymbol(r'$');

    await settle(tester);
    await sync.flushNow();
    await settle(tester);

    // ── assert every table received rows ─────────────────────────────────
    for (final t in const [
      'accounts', 'transactions', 'categories', 'credit_cards', 'loans',
      'budgets', 'investments', 'goals', 'recurring_payments', 'notes', 'user_settings',
    ]) {
      expect(fake.rowCount(t), greaterThan(0), reason: 'no cloud rows for "$t"');
    }
    expect(fake.row('accounts', accId), isNotNull);
    expect((fake.store['user_settings']!.values.first)['currency_symbol'], r'$');

    // ── realtime: a remote goal upsert lands in live app state ───────────
    final remoteGoal = GoalModel(
      id: 'rt-goal-1',
      name: 'Pushed From Cloud',
      targetAmount: 999,
      currentSavedAmount: 10,
      updatedAt: DateTime.now().toUtc(),
    ).toCloudJson();
    fake.pushRemote(RemoteChange(
      table: 'goals',
      op: 'upsert',
      row: remoteGoal,
      updatedAt: DateTime.now(),
    ));
    await pumpUntil(
      tester,
      () => container.read(financeNotifierProvider).goals.any((g) => g.id == 'rt-goal-1'),
    );
    expect(
      container.read(financeNotifierProvider).goals.firstWhere((g) => g.id == 'rt-goal-1').name,
      'Pushed From Cloud',
    );

    // ── delete propagates as a tombstone ────────────────────────────────
    finance.deleteAccount(accId);
    await settle(tester);
    await sync.flushNow();
    await settle(tester);
    expect(fake.row('accounts', accId)?['is_deleted'], true,
        reason: 'deleted account pushed as tombstone');
    expect(
      container.read(financeNotifierProvider).accounts.any((a) => a.id == accId),
      isFalse,
      reason: 'deleted account gone from live state',
    );
  });
}
