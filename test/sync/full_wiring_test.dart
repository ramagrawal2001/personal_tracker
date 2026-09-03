// Real provider-graph wiring test — no widgets, so it runs headless in the
// normal `flutter test` suite. Uses the REAL syncServiceProvider (with its
// auth listener), the REAL FinanceNotifier / NotesNotifier, an in-memory Drift
// db and a fake cloud gateway. Drives auth -> asserts the whole sync path:
// backfill on login, write-through of every entity, realtime merge, and
// tombstone delete propagation.

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/providers/notes_provider.dart';
import 'package:aspyric/core/sync/cloud_gateway.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:aspyric/features/auth/presentation/auth_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_gateway.dart';

Future<void> _tick([int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _until(bool Function() cond, {int tries = 60}) async {
  for (var i = 0; i < tries; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeCloudGateway fake;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fake = FakeCloudGateway();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudGatewayProvider.overrideWithValue(fake),
    ]);
    // Instantiate the sync service so its auth listener is registered.
    container.read(syncServiceProvider);
  });

  tearDown(() async {
    await container.read(syncServiceProvider).stop();
    container.dispose();
    await fake.dispose();
    await db.close();
  });

  test('login -> backfill -> per-entity write-through -> realtime -> tombstone delete', () async {
    // Force the notifiers to construct + run _loadPersistedState so the default
    // categories are written to Drift *before* login triggers the backfill.
    final finance = container.read(financeNotifierProvider.notifier);
    final notes = container.read(notesProvider.notifier);
    await _until(() => container.read(financeNotifierProvider).categories.isNotEmpty);

    // ── sign in via the real AuthNotifier (debug demo bypass) ─────────────
    await container.read(authNotifierProvider.notifier).signIn('test@aspyric.app', 'Aspyric@123');
    expect(container.read(authNotifierProvider).isAuthenticated, isTrue);

    // let the auth listener's svc.start(uid) run, then force completion
    final sync = container.read(syncServiceProvider);
    await _until(() => sync.isStarted);
    await _until(() => fake.rowCount('user_settings') == 1, tries: 80);
    await sync.flushNow();
    await _tick();

    // backfill seeded the default categories + a user_settings row
    expect(fake.rowCount('user_settings'), 1);
    expect(fake.rowCount('categories'), greaterThan(0));

    finance.addAccount(name: 'WChecking', type: AccountType.savingsAccount, openingBalance: 1000);
    final accId = container.read(financeNotifierProvider).accounts.last.id;
    final catId = container.read(financeNotifierProvider).categories.first.id;

    finance.addTransaction(
      accountId: accId, type: TransactionType.expense, amount: 42.5,
      categoryId: catId, merchant: 'WStore', date: DateTime.now(),
    );
    finance.addCategory(name: 'WCat', type: 'expense', icon: 'tag');
    finance.addCreditCard(
      name: 'WCard', bank: 'WBank', last4: '4242',
      creditLimit: 5000, statementDay: 1, dueDay: 15,
    );
    finance.addLoan(
      name: 'WLoan', provider: 'WFin', principalAmount: 20000,
      interestRate: 9.5, monthlyEmi: 1800, dueDay: 5, tenureMonths: 12,
    );
    finance.addBudget(categoryId: catId, monthlyLimit: 3000);
    finance.addInvestment(
      name: 'WSip', type: InvestmentType.stocks, investedAmount: 10000, currentValue: 11000,
    );
    finance.addGoal(name: 'WGoal', targetAmount: 50000, currentSavedAmount: 5000);
    finance.addRecurringPayment(
      title: 'WRent', amount: 15000, frequency: PaymentFrequency.monthly,
      nextDueDate: DateTime.now().add(const Duration(days: 3)),
    );
    notes.saveNote(notes.createNote().copyWith(title: 'WNote', body: 'hello cloud'));
    finance.setCurrencySymbol(r'$');

    await _tick();
    await sync.flushNow();
    await _tick();

    for (final t in const [
      'accounts', 'transactions', 'categories', 'credit_cards', 'loans',
      'budgets', 'investments', 'goals', 'recurring_payments', 'notes', 'user_settings',
    ]) {
      expect(fake.rowCount(t), greaterThan(0), reason: 'no cloud rows for "$t"');
    }
    expect(fake.row('accounts', accId), isNotNull);
    expect(fake.store['user_settings']!.values.first['currency_symbol'], r'$');

    // ── realtime: a remote goal upsert converges into live state ─────────
    final remoteGoal = GoalModel(
      id: 'rt-goal-1', name: 'Pushed From Cloud',
      targetAmount: 999, currentSavedAmount: 10,
      updatedAt: DateTime.now().toUtc(),
    ).toCloudJson();
    fake.pushRemote(RemoteChange(
      table: 'goals', op: 'upsert', row: remoteGoal, updatedAt: DateTime.now(),
    ));
    await _tick();
    final goals = container.read(financeNotifierProvider).goals;
    expect(goals.any((g) => g.id == 'rt-goal-1'), isTrue, reason: 'realtime goal not merged');
    expect(goals.firstWhere((g) => g.id == 'rt-goal-1').name, 'Pushed From Cloud');

    // ── delete propagates as a tombstone ───────────────────────────────
    finance.deleteAccount(accId);
    await _tick();
    await sync.flushNow();
    await _tick();
    expect(fake.row('accounts', accId)?['is_deleted'], true);
    expect(container.read(financeNotifierProvider).accounts.any((a) => a.id == accId), isFalse);
  });
}
