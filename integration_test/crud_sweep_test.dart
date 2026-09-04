// CRUD sweep — device entrypoint.
//
// Drives the real create → edit → delete round-trip for every core module
// (accounts, categories, transactions incl. transfer, budgets, goals, notes,
// credit cards, loans, recurring payments, investments) through the actual
// widgets against the real `AspyricApp`, signed in with the debug demo bypass.
//
// Run:  flutter test integration_test/crud_sweep_test.dart -d chrome
//
// The scenario body lives in crud_sweep_scenario.dart and is shared with the
// headless `flutter test` regression lock in test/crud_sweep_test.dart.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'crud_sweep_scenario.dart';
import '../test/support/test_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  bootstrapTestEnv();

  testWidgets('create → edit → delete round-trips for every core module',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 3.5;
    addTearDown(tester.view.reset);

    final failures = await runCrudSweep(tester);
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
