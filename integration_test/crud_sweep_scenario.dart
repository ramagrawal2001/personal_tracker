// Shared CRUD-sweep scenario — drives the real create → edit → delete
// round-trip for every core module through the actual widgets (modals, sheets,
// dialogs, dropdowns, pickers) against the real `AspyricApp`, signed in with
// the debug demo bypass.
//
// It is imported by two entrypoints:
//   * integration_test/crud_sweep_test.dart  (IntegrationTestWidgetsFlutterBinding,
//     runnable on a device, e.g. `flutter test integration_test/crud_sweep_test.dart -d chrome`)
//   * test/crud_sweep_test.dart              (regular `flutter test` suite)
//
// Every module is wrapped so one broken flow doesn't mask the rest — the list
// of failure strings is returned for the caller to assert on.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';

import 'package:aspyric/main.dart';
import 'package:aspyric/core/router/app_router.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/providers/notes_provider.dart';

Future<List<String>> runCrudSweep(WidgetTester tester) async {
  // Splash / chart tickers keep frames scheduled, so pumpAndSettle would hang —
  // use a bounded pump budget (the pattern full_sweep_test.dart uses).
  Future<void> settle({int frames = 28}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpUntil(bool Function() cond, {int frames = 200}) async {
    for (var i = 0; i < frames; i++) {
      if (cond()) return;
      await tester.pump(const Duration(milliseconds: 70));
    }
  }

  bool present(String s) => find.text(s).evaluate().isNotEmpty;

  FinanceNotifier seeded(AppDatabase db) {
    final n = FinanceNotifier(db, autoLoad: false);
    n.addAccount(
        name: 'HDFC Savings',
        type: AccountType.savingsAccount,
        bank: 'HDFC',
        openingBalance: 100000);
    n.addAccount(
        name: 'Cash Wallet', type: AccountType.cash, openingBalance: 20000);
    return n;
  }

  // Plugin stubs so the real app can boot under a plain `flutter test` binding
  // (on a device these are provided natively). Harmless when already provided.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const <String>[
    'plugins.it_nomads.com/flutter_secure_storage',
    'plugins.flutter.io/local_auth',
    'plugins.flutter.io/local_auth_darwin',
    'dexterous.com/flutter/local_notifications',
    'plugins.flutter.io/path_provider',
    'plugins.flutter.io/path_provider_macos',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
      if (call.method == 'read' || call.method == 'readAll') return null;
      if (call.method.startsWith('getTemporaryDirectory') ||
          call.method.startsWith('getApplicationDocumentsDirectory') ||
          call.method.startsWith('getApplicationSupportDirectory')) {
        return '/tmp';
      }
      return null;
    });
  }

  final failures = <String>[];
  final db = AppDatabase.forTesting(NativeDatabase.memory());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        financeNotifierProvider.overrideWith((ref) => seeded(db)),
      ],
      child: const AspyricApp(),
    ),
  );
  await pumpUntil(
      () => present('Sign In to Aspyric') && find.byType(TextField).evaluate().length >= 2,
      frames: 400);
  await settle();

  final loginFields = find.byType(TextField);
  if (loginFields.evaluate().length < 2) {
    return ['login: expected email+password fields, found '
        '${loginFields.evaluate().length} (splash never handed off to login)'];
  }
  await tester.enterText(loginFields.at(0), 'test@aspyric.app');
  await tester.enterText(loginFields.at(1), 'Aspyric@123');
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
  await pumpUntil(() => present('Dashboard'), frames: 400);
  await settle();
  if (!present('Dashboard')) {
    return ['login: never reached Dashboard after Sign In'];
  }

  final container =
      ProviderScope.containerOf(tester.element(find.byType(AspyricApp)));
  final router = container.read(appRouterProvider);
  final finance = container.read(financeNotifierProvider.notifier);
  FinanceState fs() => container.read(financeNotifierProvider);

  Future<void> go(String route) async {
    router.go(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await settle();
  }

  Finder appBarPlus() => find.descendant(
      of: find.byType(AppBar), matching: find.byIcon(LucideIcons.plus));

  Future<void> tapText(String s) async {
    await tester.ensureVisible(find.text(s).last);
    await tester.tap(find.text(s).last, warnIfMissed: false);
    await settle();
  }

  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
      final ex = tester.takeException();
      if (ex != null) failures.add('$name: threw $ex');
    } catch (e, st) {
      final where = st.toString().split('\n').firstWhere(
          (l) => l.contains('crud_sweep_scenario.dart'),
          orElse: () => st.toString().split('\n').first);
      failures.add('$name: $e   @ ${where.trim()}');
    }
  }

  // ───────────────────────────── ACCOUNTS ──────────────────────────────
  await step('accounts', () async {
    await go('/accounts');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Add New Account'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Acct');
    await tester.enterText(tf.at(3), '5000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
    await pumpUntil(() => present('Sweep Acct'));
    if (!present('Sweep Acct')) {
      failures.add('accounts: created row not visible');
      return;
    }
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle();
    await tapText('Edit');
    await pumpUntil(() => present('Edit Account'));
    await settle();
    await tester.enterText(find.byType(TextField).at(0), 'Sweep Acct Renamed');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await pumpUntil(() => present('Sweep Acct Renamed'));
    if (!present('Sweep Acct Renamed')) {
      failures.add('accounts: rename not reflected in list');
    }
    final renamed =
        fs().accounts.firstWhere((a) => a.name == 'Sweep Acct Renamed');
    await tester.tap(find.byIcon(LucideIcons.moreVertical).at(2));
    await settle();
    await tapText('Delete');
    await pumpUntil(() =>
        find.widgetWithText(ElevatedButton, 'Delete').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await settle();
    if (fs().accounts.any((a) => a.id == renamed.id)) {
      failures.add('accounts: still present after delete');
    }
  });

  // ──────────────────────────── CATEGORIES ─────────────────────────────
  await step('categories', () async {
    await go('/categories');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Add Category'));
    await settle();
    await tester.enterText(find.byType(TextField).first, 'Sweep Cat');
    final save = find.widgetWithText(ElevatedButton, 'Save Category');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => present('Sweep Cat'));
    if (!present('Sweep Cat')) {
      failures.add('categories: created row not visible');
      return;
    }
    final cat = fs().categories.firstWhere((c) => c.name == 'Sweep Cat');
    await tester.tap(find.byIcon(LucideIcons.pencil).last);
    await pumpUntil(() => present('Edit Category'));
    await settle();
    await tester.enterText(find.byType(TextField).first, 'Sweep Cat 2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await pumpUntil(() => fs().categories.any((c) => c.name == 'Sweep Cat 2'));
    if (!fs().categories.any((c) => c.id == cat.id && c.name == 'Sweep Cat 2')) {
      failures.add('categories: rename not persisted to state');
    }
    await tester.tap(find.byIcon(LucideIcons.trash2).last);
    await pumpUntil(() => present('Delete category?'));
    await settle();
    await tapText('Delete');
    await settle();
    if (fs().categories.any((c) => c.id == cat.id)) {
      failures.add('categories: still present after delete');
    }
  });

  // ─────────────────────────── TRANSACTIONS ────────────────────────────
  await step('transaction-expense', () async {
    await go('/transactions');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Log Transaction'));
    await settle();
    await tester.enterText(find.byType(TextField).at(0), '750');
    await tester.enterText(find.byType(TextField).at(1), 'SweepMerchant');
    final save = find.widgetWithText(ElevatedButton, 'Save Transaction');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => present('SweepMerchant'));
    if (!present('SweepMerchant')) {
      failures.add('transaction-expense: created row not visible');
      return;
    }
    await tapText('SweepMerchant');
    await pumpUntil(() => present('Edit Transaction'));
    await settle();
    await tester.enterText(find.byType(TextField).at(0), '999');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await pumpUntil(() => fs()
        .transactions
        .any((t) => t.merchant == 'SweepMerchant' && t.amount == 999));
    if (!fs()
        .transactions
        .any((t) => t.merchant == 'SweepMerchant' && t.amount == 999)) {
      failures.add('transaction-expense: amount edit not persisted');
    }
    await tester.drag(
        find.ancestor(
            of: find.text('SweepMerchant'), matching: find.byType(Dismissible)),
        const Offset(-600, 0));
    await settle();
    if (present('Delete transaction?')) {
      await tapText('Delete');
      await settle();
    }
    if (fs().transactions.any((t) => t.merchant == 'SweepMerchant')) {
      failures.add('transaction-expense: still present after swipe-delete');
    }
  });

  await step('transaction-transfer', () async {
    final before = fs()
        .accountsWithCalculatedBalances
        .firstWhere((a) => a.name == 'HDFC Savings')
        .calculatedBalance;
    await go('/transactions');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Log Transaction'));
    await settle();
    await tapText('Transfer');
    await pumpUntil(() => present('To Destination Account'));
    await settle();
    await tester.enterText(find.byType(TextField).at(0), '3000');
    final save = find.widgetWithText(ElevatedButton, 'Save Transaction');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle();
    final txs = fs()
        .transactions
        .where((t) => t.type == TransactionType.transfer && t.amount == 3000)
        .toList();
    if (txs.isEmpty) {
      failures.add('transaction-transfer: transfer not created');
      return;
    }
    final after = fs()
        .accountsWithCalculatedBalances
        .firstWhere((a) => a.name == 'HDFC Savings')
        .calculatedBalance;
    if ((before - after - 3000).abs() > 0.01) {
      failures.add(
          'transaction-transfer: source balance did not drop by 3000 (before=$before after=$after)');
    }
    finance.deleteTransaction(txs.first.id);
    await settle();
  });

  // ────────────────────────────── BUDGETS ──────────────────────────────
  await step('budgets', () async {
    await go('/budgets');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('New Monthly Budget'));
    await settle();
    await tester.enterText(find.byType(TextField).first, '15000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Budget'));
    await pumpUntil(() => fs().budgets.isNotEmpty);
    if (fs().budgets.isEmpty) {
      failures.add('budgets: not created');
      return;
    }
    final b = fs().budgets.first;
    await tester.tap(find.byIcon(LucideIcons.moreVertical).first);
    await settle();
    await tapText('Edit Limit');
    await pumpUntil(() => present('Edit Budget Limit'));
    await settle();
    await tester.enterText(find.byType(TextField).first, '22000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await pumpUntil(
        () => fs().budgets.any((x) => x.id == b.id && x.monthlyLimit == 22000));
    if (!fs().budgets.any((x) => x.id == b.id && x.monthlyLimit == 22000)) {
      failures.add('budgets: limit edit not persisted');
    }
    await tester.tap(find.byIcon(LucideIcons.moreVertical).first);
    await settle();
    await tapText('Delete');
    await pumpUntil(() =>
        find.widgetWithText(ElevatedButton, 'Delete').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await settle();
    if (fs().budgets.any((x) => x.id == b.id)) {
      failures.add('budgets: still present after delete');
    }
  });

  // ─────────────────────────────── GOALS ───────────────────────────────
  await step('goals', () async {
    await go('/goals');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Create Savings Goal'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Goal');
    await tester.enterText(tf.at(1), '50000');
    await tester.enterText(tf.at(2), '10000');
    final save = find.widgetWithText(ElevatedButton, 'Save Savings Goal');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().goals.any((g) => g.name == 'Sweep Goal'));
    if (!fs().goals.any((g) => g.name == 'Sweep Goal')) {
      failures.add('goals: not created');
      return;
    }
    await go('/goals');
    final g = fs().goals.firstWhere((g) => g.name == 'Sweep Goal');
    await tapText('Add Funds');
    await pumpUntil(() => present('Deposit to Sweep Goal'));
    await settle();
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Deposit'));
    await pumpUntil(() =>
        fs().goals.firstWhere((x) => x.id == g.id).currentSavedAmount == 15000);
    if (fs().goals.firstWhere((x) => x.id == g.id).currentSavedAmount != 15000) {
      failures.add('goals: add-funds not applied');
    }
    await tester.tap(find.byIcon(LucideIcons.pencil).first);
    await pumpUntil(() => present('Edit Goal'));
    await settle();
    await tester.enterText(find.byType(TextField).at(0), 'Sweep Goal 2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await pumpUntil(
        () => fs().goals.any((x) => x.id == g.id && x.name == 'Sweep Goal 2'));
    if (!fs().goals.any((x) => x.id == g.id && x.name == 'Sweep Goal 2')) {
      failures.add('goals: rename not persisted');
    }
    await tester.tap(find.byIcon(LucideIcons.trash2).first);
    await pumpUntil(() => present('Delete goal?'));
    await settle();
    await tapText('Delete');
    await settle();
    if (fs().goals.any((x) => x.id == g.id)) {
      failures.add('goals: still present after delete');
    }
  });

  // ─────────────────────────────── NOTES ───────────────────────────────
  NotesState ns() => container.read(notesProvider);
  await step('notes-text', () async {
    await go('/notes');
    await tester.tap(find.byType(FloatingActionButton).first);
    await pumpUntil(() => find.text('Title').evaluate().isNotEmpty);
    await settle();
    await tester.enterText(find.byType(TextField).at(0), 'Sweep Note');
    await tester.enterText(find.byType(TextField).at(1), 'body text here');
    await settle();
    await tester.tap(find.byIcon(LucideIcons.arrowLeft));
    await settle();
    if (!ns().notes.any((n) => n.title == 'Sweep Note')) {
      failures.add('notes-text: note not saved on back');
      return;
    }
    await tapText('Sweep Note');
    await pumpUntil(() => find.byIcon(LucideIcons.arrowLeft).evaluate().isNotEmpty);
    await settle();
    await tester.enterText(find.byType(TextField).at(0), 'Sweep Note Edited');
    await tester.tap(find.byIcon(LucideIcons.arrowLeft));
    await settle();
    if (!ns().notes.any((n) => n.title == 'Sweep Note Edited')) {
      failures.add('notes-text: edit not saved');
    }
    final n = ns().notes.firstWhere((n) => n.title == 'Sweep Note Edited');
    await tester.tap(find.byIcon(LucideIcons.trash2).first);
    await pumpUntil(() => present('Delete note?'));
    await settle();
    await tapText('Delete');
    await settle();
    if (ns().notes.any((x) => x.id == n.id)) {
      failures.add('notes-text: still present after delete');
    }
  });

  await step('notes-checklist', () async {
    await go('/notes');
    await tester.tap(find.byType(FloatingActionButton).first);
    await pumpUntil(() => find.text('Title').evaluate().isNotEmpty);
    await settle();
    await tester.enterText(find.byType(TextField).at(0), 'Sweep Checklist');
    await tester.tap(find.byIcon(LucideIcons.checkSquare).first);
    await settle();
    await tester.tap(find.widgetWithText(TextButton, 'Add item'));
    await settle();
    await tester.enterText(find.byType(TextField).last, 'first item');
    await settle();
    await tester.tap(find.byIcon(LucideIcons.arrowLeft));
    await settle();
    final made =
        ns().notes.where((n) => n.title == 'Sweep Checklist').toList();
    if (made.isEmpty ||
        !made.first.isChecklist ||
        made.first.checklistItems.isEmpty) {
      failures.add(
          'notes-checklist: checklist note not saved with items ($made)');
    }
    if (made.isNotEmpty) {
      container.read(notesProvider.notifier).deleteNote(made.first.id);
    }
    await settle();
  });

  // ─────────── lighter create+delete for the remaining modules ──────────
  await step('credit-cards', () async {
    await go('/credit-cards');
    final before = fs().creditCards.length;
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await pumpUntil(() => present('Add New Card'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Card');
    await tester.enterText(tf.at(1), 'SweepBank');
    await tester.enterText(tf.at(2), '4242');
    await tester.enterText(tf.at(3), 'Sweep Holder');
    final save = find.widgetWithText(ElevatedButton, 'Add Card to Vault');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().creditCards.length == before + 1);
    if (fs().creditCards.length != before + 1) {
      failures.add('credit-cards: card not created');
      return;
    }
    finance.deleteCard(fs().creditCards.last.id);
    await settle();
  });

  await step('loans', () async {
    await go('/loans');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Add Loan / EMI'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Loan');
    await tester.enterText(tf.at(1), 'SweepBank');
    await tester.enterText(tf.at(2), '500000');
    await tester.enterText(tf.at(3), '9');
    await tester.enterText(tf.at(4), '10000');
    await tester.enterText(tf.at(5), '60');
    final save = find.widgetWithText(ElevatedButton, 'Add Loan');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().loans.isNotEmpty);
    if (fs().loans.isEmpty) {
      failures.add('loans: not created');
      return;
    }
    finance.deleteLoan(fs().loans.last.id);
    await settle();
  });

  await step('recurring', () async {
    await go('/recurring');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('New Recurring Payment'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Sub');
    await tester.enterText(tf.at(1), '499');
    final save = find.widgetWithText(ElevatedButton, 'Add Payment');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().recurringPayments.isNotEmpty);
    if (fs().recurringPayments.isEmpty) {
      failures.add('recurring: not created');
      return;
    }
    finance.deleteRecurringPayment(fs().recurringPayments.last.id);
    await settle();
  });

  await step('investments', () async {
    await go('/investments');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Add Asset / Investment'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Fund');
    await tester.enterText(tf.at(1), '100000');
    await tester.enterText(tf.at(2), '120000');
    final save = find.widgetWithText(ElevatedButton, 'Save Investment');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().investments.isNotEmpty);
    if (fs().investments.isEmpty) {
      failures.add('investments: not created');
      return;
    }
    finance.deleteInvestment(fs().investments.last.id);
    await settle();
  });

  // ignore: avoid_print
  print('\n════ CRUD SWEEP ════ failures: ${failures.length}');
  for (final f in failures) {
    // ignore: avoid_print
    print(' x $f');
  }
  return failures;
}
