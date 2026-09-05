// Headless counterpart of integration_test/salary_flow_test.dart — same
// scenario body, run under the regular `flutter test` binding so it's part
// of the fast CI suite too (mirrors test/crud_sweep_test.dart's relationship
// to integration_test/crud_sweep_test.dart).
//
// Run:  flutter test test/salary_flow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/salary_flow_scenario.dart';

void main() {
  testWidgets('Companies, PF investment, Log Salary, and card fixes all work end-to-end',
      (WidgetTester tester) async {
    // Wider than crud_sweep_scenario's default — narrower logical widths trip
    // a pre-existing (unrelated) overflow in login_screen.dart's "Register" /
    // legal-links rows that isn't part of this feature.
    tester.view.physicalSize = const Size(1600, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Pass --dart-define=SCREENSHOT_DIR=/absolute/path to capture real
    // rendered frames at key checkpoints for visual verification — no-op
    // (and no disk access) otherwise.
    const screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');
    final failures = await runSalaryFlowSweep(tester, screenshotDir: screenshotDir.isEmpty ? null : screenshotDir);
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
