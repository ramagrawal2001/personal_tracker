import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/l10n/app_localizations.dart';
import 'package:aspyric/features/accounts/presentation/add_account_modal.dart';
import 'package:aspyric/features/categories/presentation/add_category_modal.dart';
import 'package:aspyric/features/auth/presentation/profile_screen.dart';
import 'package:aspyric/features/navigation/main_shell.dart';

import 'test_helpers.dart';

/// Regression guard for the "form content hides behind the on-screen keyboard"
/// class of bug.
///
/// Every routed screen renders a per-screen [Scaffold] (AppScaffold / raw)
/// nested inside the navigation shell's [Scaffold]. The shell re-injects a
/// [MediaQuery] for its child that still carries the full `viewInsets.bottom`
/// (it is derived from a context *above* the shell Scaffold), so BOTH scaffolds
/// used to inset the body by the keyboard height — subtracting it twice and
/// collapsing a form's scroll viewport to a few pixels ("blank space between
/// the app bar and the keyboard"). The fix: the shell no longer resizes for the
/// keyboard, leaving the inner Scaffold as the single owner of that behaviour.
///
/// These tests inject a fake 350px bottom view-inset (a keyboard) and assert:
///  (a) the inputs still render,
///  (b) nothing throws / overflows (`tester.takeException()` is null),
///  (c) the primary action button can be brought fully above the keyboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double kScreenH = 800;
  const double kScreenW = 400;
  const double kKeyboard = 350;
  // Anything at or below this Y is behind the keyboard.
  const double kFold = kScreenH - kKeyboard;

  setUp(() {
    // AuthNotifier's session-restore probe reads SharedPreferences; give it a
    // clean in-memory store so nothing throws post-frame.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  void applyPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(kScreenW, kScreenH);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: kKeyboard);
    addTearDown(tester.view.reset);
  }

  Widget wrapApp(Widget app) => ProviderScope(
        overrides: [
          financeNotifierProvider
              .overrideWith((ref) => createTestFinanceNotifier()),
        ],
        child: app,
      );

  testWidgets('Profile edit screen keeps its fields usable under a keyboard',
      (tester) async {
    applyPhoneViewport(tester);

    // The real navigation shell — this is what re-injects the MediaQuery that
    // used to cause the double inset.
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(wrapApp(
      MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    // Enter edit mode.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // (a) inputs render
    expect(find.byType(TextField), findsWidgets);

    // (b) no overflow / exception from the injected inset
    expect(tester.takeException(), isNull);

    // The scroll viewport must NOT have collapsed. With the double-inset bug it
    // shrinks to a handful of pixels; with the fix it stays roughly
    // (screen - shell header - app bar - keyboard) ~= 350px tall.
    final scrollableSize = tester.getSize(
      find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollableSize.height, greaterThan(200),
        reason: 'form scroll viewport collapsed behind the keyboard');

    // (c) the primary action button can be scrolled fully above the keyboard
    await _expectActionAboveKeyboard(tester, 'Save Changes', kFold);
  });

  Future<void> pumpModalHost(
    WidgetTester tester,
    void Function(BuildContext) open,
  ) async {
    await tester.pumpWidget(wrapApp(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> assertModalClearsKeyboard(
    WidgetTester tester,
    String primaryLabel,
  ) async {
    // (a) inputs render inside the sheet
    expect(find.byType(TextField), findsWidgets);
    // (b) no overflow / exception (guards e.g. an unbounded DropdownButton)
    expect(tester.takeException(), isNull);
    // (c) primary button reachable above the keyboard
    await _expectActionAboveKeyboard(tester, primaryLabel, kFold);
  }

  testWidgets('AddAccountModal grows with the keyboard', (tester) async {
    applyPhoneViewport(tester);
    await pumpModalHost(tester, (ctx) => AddAccountModal.show(ctx));
    await assertModalClearsKeyboard(tester, 'Create Account');
  });

  testWidgets('AddCategoryModal grows with the keyboard', (tester) async {
    applyPhoneViewport(tester);
    await pumpModalHost(tester, (ctx) => AddCategoryModal.show(ctx));
    await assertModalClearsKeyboard(tester, 'Save Category');
  });
}

/// Scrolls the labelled action button into view and asserts it ends up fully
/// above the on-screen keyboard (`fold`) and still hit-testable — i.e. it is
/// not stranded behind the keyboard.
Future<void> _expectActionAboveKeyboard(
  WidgetTester tester,
  String label,
  double fold,
) async {
  final target = find.text(label);
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final r = tester.getRect(target);
  expect(r.top, greaterThanOrEqualTo(0.0));
  expect(r.bottom, lessThanOrEqualTo(fold + 1.0),
      reason: '"$label" action is hidden behind the keyboard');
  expect(target.hitTestable(), findsOneWidget,
      reason: '"$label" action is not hit-testable');
}
