import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aspyric/features/navigation/main_shell.dart' show backTarget, kRootTabPaths;

/// These tests lock in the app-wide back-navigation contract:
///
///  * "secondary" screens reached from the **More** sheet (Settings, Cards,
///    Loans, …) are `context.push`ed, so they sit on the navigation stack and a
///    system back gesture returns to the opener instead of exiting the app.
///  * root tab destinations (`/`, `/transactions`, `/accounts`, `/notes`) have
///    nothing to pop; a back gesture there is a genuine app-exit request.
///
/// The full [appRouterProvider] pulls in google_fonts / Supabase / an
/// auto-loading Drift database, which is flaky under a headless `flutter test`.
/// We therefore exercise the two moving parts directly:
///   1. [backTarget] — the pure "where does back go" decision function.
///   2. a representative [GoRouter] with the same shell shape as the real app,
///      to prove `push` yields a poppable entry and `pop` lands on the parent.
void main() {
  group('backTarget() decision table', () {
    test('a pushed page (canPop == true) is never intercepted', () {
      expect(backTarget('/settings', true), isNull);
      expect(backTarget('/credit-cards', true), isNull);
      expect(backTarget('/', true), isNull);
      expect(backTarget('/notes/editor', true), isNull);
    });

    test('root tabs with nothing to pop fall through to the OS (exit)', () {
      for (final path in kRootTabPaths) {
        expect(backTarget(path, false), isNull, reason: '$path should allow OS pop');
      }
    });

    test('a stray root-level non-tab screen redirects Home instead of exiting', () {
      expect(backTarget('/settings', false), '/');
      expect(backTarget('/analytics', false), '/');
      expect(backTarget('/profile', false), '/');
      expect(backTarget('/net-worth', false), '/');
    });

    test('kRootTabPaths is exactly the four primary destinations', () {
      expect(kRootTabPaths, {'/', '/transactions', '/accounts', '/notes'});
    });
  });

  group('GoRouter push/pop mechanics (shell route)', () {
    late GoRouter router;

    Widget dummy(String label) => Scaffold(body: Center(child: Text(label)));

    setUp(() {
      router = GoRouter(
        initialLocation: '/',
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              // Mirror MainShell: wrap the shell in the same PopScope contract.
              final target = backTarget(
                state.uri.path,
                GoRouter.of(context).canPop(),
              );
              return PopScope(
                canPop: target == null,
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop || target == null) return;
                  context.go(target);
                },
                child: child,
              );
            },
            routes: [
              GoRoute(path: '/', builder: (_, __) => dummy('DASHBOARD')),
              GoRoute(path: '/transactions', builder: (_, __) => dummy('TRANSACTIONS')),
              GoRoute(path: '/settings', builder: (_, __) => dummy('SETTINGS')),
              GoRoute(path: '/credit-cards', builder: (_, __) => dummy('CARDS')),
            ],
          ),
        ],
      );
    });

    tearDown(() => router.dispose());

    testWidgets('push(/settings) creates a poppable entry; pop() returns to /', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(router.canPop(), isFalse, reason: 'root tab has nothing to pop');

      // Simulate a More-sheet item: context.push (NOT go).
      router.push('/settings');
      await tester.pumpAndSettle();

      expect(find.text('SETTINGS'), findsOneWidget);
      expect(
        router.canPop(),
        isTrue,
        reason: 'a pushed secondary screen must have a back-stack entry',
      );

      // System back / AppBar back.
      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/',
        reason: 'back from Settings returns to its opener, it does not exit',
      );
    });

    testWidgets('chained pushes unwind one screen at a time', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.push('/settings');
      await tester.pumpAndSettle();
      router.push('/credit-cards');
      await tester.pumpAndSettle();
      expect(find.text('CARDS'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets('from a root tab the shell does not intercept back (no redirect)', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // On '/', nothing pushed: canPop is false and backTarget returns null,
      // so the shell PopScope stays permissive (canPop: true) and the OS is
      // free to exit the app rather than being bounced elsewhere.
      expect(router.canPop(), isFalse);
      expect(backTarget('/', router.canPop()), isNull);

      // A back invocation here must not change the location.
      final handled = await router.routerDelegate.popRoute();
      await tester.pumpAndSettle();
      expect(handled, isFalse, reason: 'nothing to pop -> hand back to the OS');
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    });
  });
}
