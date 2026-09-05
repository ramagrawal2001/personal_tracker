import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/widgets/biometric_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Regression test: a re-lock while the user is sitting on a pushed
/// secondary screen must not let a back press silently pop that hidden
/// route. Before this fix, `BiometricGate`'s lock screen had no `PopScope`,
/// so pop fell through to the underlying Navigator — repeat enough times
/// (or once, if there was nothing else to pop) and it exits the app while
/// the lock screen visibly never changes, which is exactly what "back
/// button closes the app" looks like from the outside.
///
/// `local_auth`'s platform channel isn't mocked under `flutter test`, so
/// `BiometricService.authenticate` always fails closed and the gate renders
/// its locked Scaffold — no extra stubbing needed to reach that state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('back press on the biometric lock screen does not pop the underlying route', (tester) async {
    // Not manually disposed: the overriding ProviderScope below takes
    // ownership and disposes it when the widget tree is torn down.
    final notifier = createTestFinanceNotifier();
    notifier.toggleBiometric(true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [financeNotifierProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          navigatorKey: GlobalKey<NavigatorState>(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BiometricGate(child: Text('UNLOCKED'))),
                  ),
                  child: const Text('open secondary screen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open secondary screen'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Biometric is enabled and the platform channel isn't mocked, so the
    // gate is showing its lock screen, not the pushed route's real content.
    expect(find.text('UNLOCKED'), findsNothing);
    expect(find.text('Unlock with Face ID or Fingerprint'), findsOneWidget);

    // Simulate a system back gesture/button.
    final handled = await tester.binding.handlePopRoute();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The lock screen must still be showing — the pop must not have gone
    // through to the Navigator underneath it.
    expect(find.text('Unlock with Face ID or Fingerprint'), findsOneWidget);
    expect(find.text('open secondary screen'), findsNothing);
    // handlePopRoute() reports whether *something* handled the pop; our
    // PopScope(canPop: false) is that something.
    expect(handled, isTrue);
  });
}
