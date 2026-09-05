// Salary / Company / PF workflow — device entrypoint.
//
// Drives Companies, PF-via-Investments, Log Salary, and the credit-card
// day-31 / edit-prefill fixes through the actual widgets against the real
// `AspyricApp`, signed in with the debug demo bypass.
//
// Run:  flutter test integration_test/salary_flow_test.dart -d <device>
//
// The scenario body lives in salary_flow_scenario.dart and is shared with
// the headless `flutter test` regression lock in test/salary_flow_test.dart.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'salary_flow_scenario.dart';
import '../test/support/test_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  bootstrapTestEnv();

  testWidgets('Companies, PF investment, Log Salary, and card fixes all work end-to-end',
      (WidgetTester tester) async {
    // Wider than crud_sweep_scenario's default — narrower logical widths trip
    // a pre-existing (unrelated) overflow in login_screen.dart's "Register" /
    // legal-links rows that isn't part of this feature.
    tester.view.physicalSize = const Size(1600, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Pass --dart-define=SCREENSHOT_DIR=/absolute/path to capture real
    // rendered frames (real fonts, unlike the headless test-font stub) at
    // key checkpoints for visual verification — no-op otherwise.
    const screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');
    final failures = await runSalaryFlowSweep(tester, screenshotDir: screenshotDir.isEmpty ? null : screenshotDir);
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
