// Salary / Company / PF workflow — shared scenario, driven through the real
// widgets (modals, sheets, dropdowns) against the real `AspyricApp`, signed
// in with the debug demo bypass. Also covers two smaller fixes from the same
// session: the credit-card statement/due-day dropdown now offering day 31,
// and the Edit Card sheet pre-filling decrypted sensitive details.
//
// It is imported by two entrypoints, exactly like crud_sweep_scenario.dart:
//   * integration_test/salary_flow_test.dart  (on-device: `flutter test
//     integration_test/salary_flow_test.dart -d <device>`)
//   * test/salary_flow_test.dart              (headless `flutter test` suite)
//
// Every module is wrapped so one broken flow doesn't mask the rest — the
// list of failure strings is returned for the caller to assert on.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:aspyric/features/transactions/presentation/log_salary_modal.dart';

/// True for a `RenderFlex overflowed by 0.NNN pixels` layout warning under
/// 1px — pure floating-point rounding noise from the test harness's chosen
/// window size, not a real overflow bug. Anything ≥1px still fails the step.
bool _isSubPixelOverflow(Object ex) {
  final m = RegExp(r'overflowed by ([\d.]+) pixels').firstMatch(ex.toString());
  if (m == null) return false;
  final amount = double.tryParse(m.group(1)!);
  return amount != null && amount < 1.0;
}

Future<List<String>> runSalaryFlowSweep(WidgetTester tester, {String? screenshotDir}) async {
  // Visual verification, on request — captures the actual rendered frame
  // (not a mock/description of it) to disk at key checkpoints. No-op unless
  // screenshotDir is passed, so normal CI runs of this test don't touch disk.
  var shotIndex = 0;
  final screenshotKey = GlobalKey();
  Future<void> shot(String name) async {
    if (screenshotDir == null) return;
    await tester.pump(const Duration(milliseconds: 100));
    final boundary = screenshotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // toImage()/toByteData() need real event-loop ticks — under the widget
    // test binding's fake clock they hang forever unless run inside
    // tester.runAsync (only available on the VM, hence the on-device
    // integration_test entrypoint not wiring screenshotDir through).
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$screenshotDir/${(shotIndex++).toString().padLeft(2, '0')}_$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }
  // Splash / chart tickers keep frames scheduled, so pumpAndSettle would hang.
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

  Future<void> tapText(String s) async {
    await tester.ensureVisible(find.text(s).last);
    await tester.tap(find.text(s).last, warnIfMissed: false);
    await settle();
  }

  FinanceNotifier freshNotifier(AppDatabase db) => FinanceNotifier(db, autoLoad: false);

  Future<void> seedInto(FinanceNotifier n) async {
    await n.addAccount(
        name: 'HDFC Salary Acc', type: AccountType.savingsAccount, bank: 'HDFC', openingBalance: 50000);
  }

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  late final FinanceNotifier seededNotifier;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        financeNotifierProvider.overrideWith((ref) => seededNotifier = freshNotifier(db)),
      ],
      // Explicit RepaintBoundary so `shot()` below has a guaranteed capture
      // point — the binding's own root render object isn't one.
      child: RepaintBoundary(key: screenshotKey, child: const AspyricApp()),
    ),
  );
  ProviderScope.containerOf(tester.element(find.byType(AspyricApp))).read(financeNotifierProvider);
  await seedInto(seededNotifier);
  await pumpUntil(() => present('Sign In to Aspyric') && find.byType(TextField).evaluate().length >= 2, frames: 400);
  await settle();

  final loginFields = find.byType(TextField);
  if (loginFields.evaluate().length < 2) {
    return ['login: expected email+password fields, found ${loginFields.evaluate().length}'];
  }
  await tester.enterText(loginFields.at(0), 'test@aspyric.app');
  await tester.enterText(loginFields.at(1), 'Aspyric@123');
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
  await pumpUntil(() => present('Dashboard'), frames: 400);
  await settle();
  if (!present('Dashboard')) {
    return ['login: never reached Dashboard after Sign In'];
  }

  final container = ProviderScope.containerOf(tester.element(find.byType(AspyricApp)));
  final router = container.read(appRouterProvider);
  final finance = container.read(financeNotifierProvider.notifier);
  FinanceState fs() => container.read(financeNotifierProvider);

  Future<void> go(String route) async {
    router.go(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await settle();
  }

  Finder appBarPlus() => find.descendant(of: find.byType(AppBar), matching: find.byIcon(LucideIcons.plus));

  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
      final ex = tester.takeException();
      if (ex != null && !_isSubPixelOverflow(ex)) failures.add('$name: threw $ex');
    } catch (e, st) {
      final where = st.toString().split('\n').firstWhere(
          (l) => l.contains('salary_flow_scenario.dart'),
          orElse: () => st.toString().split('\n').first);
      failures.add('$name: $e   @ ${where.trim()}');
    }
  }

  final account = fs().accounts.single;

  // ───────────────────────────── COMPANIES ─────────────────────────────
  await step('companies', () async {
    await go('/companies');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Add Company'));
    await settle();
    await tester.enterText(find.byType(TextField).first, 'Acme Corp');
    final save = find.widgetWithText(ElevatedButton, 'Add Company');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().companies.isNotEmpty);
    if (fs().companies.isEmpty) {
      failures.add('companies: not created');
      return;
    }
    if (fs().companies.single.name != 'Acme Corp') {
      failures.add('companies: name mismatch (${fs().companies.single.name})');
    }
    await shot('companies_list');
  });
  if (fs().companies.isEmpty) return failures;
  final company = fs().companies.single;

  // ─────────────────────── PF INVESTMENT (EPF type) ─────────────────────
  await step('pf-investment', () async {
    await go('/investments');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Add Asset / Investment'));
    await settle();
    // Open the Asset Category dropdown and pick "EPF / PF".
    await tester.tap(find.byType(DropdownButtonFormField<InvestmentType>));
    await settle();
    await tester.tap(find.text('EPF / PF').last);
    await settle();
    if (!present('UAN / Reference Number (Optional)')) {
      failures.add('pf-investment: reference-number field did not appear after selecting EPF');
    }
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'My EPF');
    await tester.enterText(tf.at(1), 'UAN123456'); // reference number
    await tester.enterText(tf.at(2), '50000'); // invested
    await tester.enterText(tf.at(3), '50000'); // current value
    await shot('add_epf_investment_form');
    final save = find.widgetWithText(ElevatedButton, 'Save Investment');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().investments.isNotEmpty);
    if (fs().investments.isEmpty) {
      failures.add('pf-investment: not created');
      return;
    }
    final inv = fs().investments.single;
    if (inv.type != InvestmentType.epf) {
      failures.add('pf-investment: type is ${inv.type}, expected epf');
    }
    if (inv.referenceNumber != 'UAN123456') {
      failures.add('pf-investment: referenceNumber not saved (${inv.referenceNumber})');
    }
  });
  if (fs().investments.isEmpty) return failures;
  final pfInvestment = fs().investments.single;

  // ───────────────────────────── LOG SALARY ─────────────────────────────
  await step('log-salary', () async {
    final beforeBalance =
        fs().accountsWithCalculatedBalances.firstWhere((a) => a.id == account.id).calculatedBalance;

    await go('/transactions');
    await tester.tap(appBarPlus().first);
    await pumpUntil(() => present('Log Transaction'));
    await settle();
    await tester.tap(find.text('Income').last);
    await settle();
    await tester.tap(find.text('Got a salary credit? Log it with a company & PF breakdown →'));
    await pumpUntil(() => present('Log Salary'));
    await settle();
    if (!present('Log Salary')) {
      failures.add('log-salary: Log Salary sheet never opened after tapping the entry point');
      return;
    }

    // Scoped to the modal itself — the Transactions screen behind it has its
    // own search TextField that an unscoped find.byType would also match.
    final tf = find.descendant(of: find.byType(LogSalaryModal), matching: find.byType(TextField));
    if (tf.evaluate().length < 3) {
      failures.add('log-salary: expected 3 text fields (amount/pf/notes) in Log Salary sheet, found ${tf.evaluate().length}');
      return;
    }
    // Net amount is the first TextField.
    await tester.enterText(tf.at(0), '80000');
    await settle();
    // PF contribution is the second — entering it should reveal the PF
    // investment picker (only shown once a valid positive amount is typed).
    await tester.enterText(tf.at(1), '3600');
    await settle(frames: 10);
    if (!present('Add To')) {
      failures.add('log-salary: PF investment picker did not appear after entering a PF amount');
    }
    await shot('log_salary_form_filled');

    final save = find.widgetWithText(ElevatedButton, 'Save Salary');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(() => fs().transactions.length >= 2, frames: 300);
    await settle();
    await shot('transactions_after_salary');

    final txs = fs().transactions;
    if (txs.length < 2) {
      failures.add('log-salary: expected 2 transactions (income + PF leg), got ${txs.length}');
      return;
    }
    final incomeTx = txs.where((t) => t.type == TransactionType.income && t.companyId == company.id).toList();
    final pfTx = txs.where((t) => t.type == TransactionType.investment && t.isExternalToAccount).toList();
    if (incomeTx.isEmpty) failures.add('log-salary: no income transaction tagged with companyId');
    if (pfTx.isEmpty) failures.add('log-salary: no isExternalToAccount investment transaction');
    if (incomeTx.isNotEmpty && incomeTx.first.amount != 80000) {
      failures.add('log-salary: income amount is ${incomeTx.first.amount}, expected 80000');
    }

    // The core correctness property this whole feature exists for: the bank
    // account reflects ONLY the net amount, not net-minus-PF or net-plus-PF.
    final afterBalance =
        fs().accountsWithCalculatedBalances.firstWhere((a) => a.id == account.id).calculatedBalance;
    if ((afterBalance - beforeBalance - 80000).abs() > 0.01) {
      failures.add('log-salary: account balance moved by ${afterBalance - beforeBalance}, expected exactly 80000 '
          '(double-counting the PF deduction would show 76400 or 83600)');
    }

    // The PF investment grew by exactly the contribution.
    final updatedPf = fs().investments.firstWhere((i) => i.id == pfInvestment.id);
    if ((updatedPf.currentValue - pfInvestment.currentValue - 3600).abs() > 0.01) {
      failures.add('log-salary: PF currentValue moved by '
          '${updatedPf.currentValue - pfInvestment.currentValue}, expected 3600');
    }
    await go('/investments');
    await shot('investments_after_salary');
  });

  // ───────────────── credit card: statement/due day up to 31 ─────────────
  await step('credit-card-day-31', () async {
    await go('/credit-cards');
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await pumpUntil(() => present('Add New Card'));
    await settle();
    final tf = find.byType(TextField);
    await tester.enterText(tf.at(0), 'Sweep Card 31');
    await tester.enterText(tf.at(1), 'SweepBank');
    await tester.enterText(tf.at(2), '4242');
    await tester.enterText(tf.at(3), 'Sweep Holder');
    await tester.enterText(tf.at(4), '4111111111111111'); // card number
    await tester.enterText(tf.at(5), '123'); // CVV

    // Statement Day / Due Day are plain (non-form) int dropdowns in the Add
    // Card sheet — DropdownButton<int>, distinct from the nullable
    // DropdownButton<int?> used for expiry month/year. Both they and the
    // Save button sit well below the fold — a plain ListView(children: …)
    // still virtualizes via slivers, so nothing off-screen is mounted (and
    // find.byType won't see it) until scrolled into the cache extent. Drag
    // all the way to the bottom (extra drags past the end just clamp) so
    // the dropdowns and the Save button are mounted together.
    for (var i = 0; i < 20; i++) {
      // warnIfMissed: false — once fully scrolled, later drags legitimately
      // don't hit anything new; that's the clamp, not a bug.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400), warnIfMissed: false);
      await settle(frames: 3);
    }
    final dayDropdowns = find.byType(DropdownButton<int>);
    if (dayDropdowns.evaluate().length < 2) {
      failures.add('credit-card-day-31: expected 2 day dropdowns (statement/due), found ${dayDropdowns.evaluate().length}');
      return;
    }
    // Read the live, mounted widgets' actual configured items — this is the
    // real fix under test (List.generate(31, …), was 28) — rather than
    // driving the popup's own internal virtualized scroll, which opens as a
    // separate Overlay route and is too implementation-fragile to drag
    // through reliably in a widget test.
    for (final finder in [dayDropdowns.at(0), dayDropdowns.at(1)]) {
      final widget = tester.widget<DropdownButton<int>>(finder);
      final values = widget.items!.map((item) => item.value!).toList();
      if (!values.contains(31)) {
        failures.add('credit-card-day-31: dropdown items top out below 31 (max: ${values.reduce((a, b) => a > b ? a : b)})');
      }
    }

    final save = find.widgetWithText(ElevatedButton, 'Add Card to Vault');
    if (save.evaluate().isEmpty) {
      failures.add('credit-card-day-31: Save button not mounted even after scrolling to the bottom');
      return;
    }
    await tester.tap(save);
    await pumpUntil(() => fs().creditCards.isNotEmpty);
    if (fs().creditCards.isEmpty) {
      failures.add('credit-card-day-31: card not created');
    }
  });

  // ───────────────── credit card: edit pre-fills sensitive details ───────
  await step('credit-card-edit-prefill', () async {
    if (fs().creditCards.isEmpty) {
      failures.add('credit-card-edit-prefill: no card to edit (creation step must have failed)');
      return;
    }
    await go('/credit-cards');
    await settle();
    // Edit lives behind the card row's "⋮" popup menu, not a bare icon.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle();
    await tapText('Edit');
    // _showEditCardSheet is now async (decrypts before showing) — give it
    // room to finish before asserting the sheet appeared.
    await pumpUntil(() => present('Edit Card'), frames: 300);
    await settle();
    if (!present('Edit Card')) {
      failures.add('credit-card-edit-prefill: Edit Card sheet never appeared');
      return;
    }
    final tf = find.byType(TextField);
    // For a credit card: name(0) bank(1) holder(2) limit(3) cardNumber(4)
    // cvv(5) pin(6). Statement/Due Day are dropdowns, not TextFields.
    if (tf.evaluate().length < 7) {
      failures.add('credit-card-edit-prefill: expected 7 text fields in Edit Card, found ${tf.evaluate().length}');
      return;
    }
    await tester.ensureVisible(tf.at(4));
    await settle();
    await shot('edit_card_prefilled_secrets');
    final numberField = tester.widget<TextField>(tf.at(4));
    final cvvField = tester.widget<TextField>(tf.at(5));
    final prefilledNumber = numberField.controller?.text ?? '';
    final prefilledCvv = cvvField.controller?.text ?? '';
    if (prefilledNumber.isEmpty) {
      failures.add('credit-card-edit-prefill: card number field is blank — should show the decrypted number');
    } else if (!prefilledNumber.endsWith('1111')) {
      failures.add('credit-card-edit-prefill: card number field is "$prefilledNumber", expected to end in 1111');
    }
    if (prefilledCvv != '123') {
      failures.add('credit-card-edit-prefill: CVV field is "$prefilledCvv", expected "123"');
    }
  });

  // Clean up so this scenario doesn't leak state into anything reusing `finance`.
  for (final c in fs().companies) {
    await finance.deleteCompany(c.id);
  }
  for (final i in fs().investments) {
    await finance.deleteInvestment(i.id);
  }
  for (final c in fs().creditCards) {
    await finance.deleteCard(c.id);
  }

  // ignore: avoid_print
  print('\n════ SALARY FLOW SWEEP ════ failures: ${failures.length}');
  for (final f in failures) {
    // ignore: avoid_print
    print(' x $f');
  }
  return failures;
}
