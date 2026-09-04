import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aspyric/main.dart';
import '../test/support/test_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  bootstrapTestEnv();

  /// Pumps frames (bounded) until [condition] is satisfied or we give up.
  /// Used instead of [WidgetTester.pumpAndSettle] because the splash screen
  /// runs a looping animation that never "settles".
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    Duration step = const Duration(milliseconds: 120),
    int maxFrames = 120,
  }) async {
    for (var i = 0; i < maxFrames; i++) {
      if (condition()) return;
      await tester.pump(step);
    }
    // One more so the failure message points at the real assertion.
  }

  bool present(String text) => find.text(text).evaluate().isNotEmpty;

  /// Pumps a fixed run of frames to let a route / modal transition finish
  /// before interacting with the destination.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  group('Aspyric end-to-end journey', () {
    testWidgets(
      'sign in with the demo account, land on the dashboard, add an account',
      (WidgetTester tester) async {
        // ── 1. Launch ────────────────────────────────────────────────────────
        await tester.pumpWidget(
          const ProviderScope(child: AspyricApp()),
        );
        await pumpUntil(tester, () => present('Sign In to Aspyric'));
        expect(tester.takeException(), isNull);
        expect(find.text('Sign In to Aspyric'), findsOneWidget,
            reason: 'splash should hand off to the login screen');

        // ── 2. Sign in (debug-only demo bypass: test@aspyric.app) ────────────
        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(2),
            reason: 'login form has an email and a password field');
        await tester.enterText(textFields.at(0), 'test@aspyric.app');
        await tester.enterText(textFields.at(1), 'Aspyric@123');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
        await pumpUntil(tester, () => present('Dashboard'), maxFrames: 200);
        // Let the route transition finish so the login page is fully gone.
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // ── 3. We're authenticated and inside the shell ─────────────────────
        expect(tester.takeException(), isNull,
            reason: 'the shell (BiometricGate + MainShell + Dashboard) must '
                'build without throwing');
        expect(find.text('Dashboard'), findsWidgets);
        expect(find.text('Sign In to Aspyric'), findsNothing,
            reason: 'the login screen should be off the tree after sign-in');

        // ── 4. Navigate to Accounts via the bottom nav ─────────────────────
        // SummaryCard upper-cases its label, hence 'TOTAL LIQUID BALANCE'.
        await tester.tap(find.byTooltip('Accounts'));
        await pumpUntil(tester, () => present('TOTAL LIQUID BALANCE'),
            maxFrames: 200);
        await settle(tester);
        expect(find.text('TOTAL LIQUID BALANCE'), findsOneWidget,
            reason: 'tapping the Accounts nav item should show the Accounts screen');

        // ── 5. Open the "add account" modal from the app-bar action ────────
        final appBarPlus = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(LucideIcons.plus),
        );
        expect(appBarPlus, findsOneWidget);
        await tester.tap(appBarPlus);
        await pumpUntil(tester, () => present('Add New Account'), maxFrames: 200);
        await settle(tester);
        expect(find.text('Add New Account'), findsOneWidget);

        // ── 6. Fill it in and submit ──────────────────────────────────────
        final acctName = 'E2E Checking ${DateTime.now().millisecondsSinceEpoch}';
        final modalFields = find.byType(TextField);
        await tester.enterText(modalFields.at(0), acctName); // Account Name
        await tester.enterText(modalFields.at(3), '12345');  // Opening Balance
        await tester.pump();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
        await pumpUntil(tester, () => present(acctName), maxFrames: 200);
        await settle(tester);

        // ── 7. The new account is rendered from the reactive store ────────
        expect(tester.takeException(), isNull);
        expect(find.text(acctName), findsOneWidget,
            reason: 'the account just written to the FinanceNotifier store '
                'should appear in the list');
      },
    );
  });
}
