import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/l10n/app_localizations.dart';
import 'package:aspyric/features/navigation/main_shell.dart';
import 'package:aspyric/features/transactions/presentation/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers three of the reported Transactions-screen gaps:
///  - the list defaults to newest-first even when transactions were inserted
///    out of date order;
///  - a sort option (amount) actually reorders the list;
///  - each row surfaces its category, not just merchant/amount/date.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget wrapApp(FinanceNotifier notifier) {
    final router = GoRouter(
      initialLocation: '/transactions',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const Scaffold(body: SizedBox())),
            GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [financeNotifierProvider.overrideWith((ref) => notifier)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  testWidgets('defaults to newest-first and shows each row\'s category', (tester) async {
    final notifier = createTestFinanceNotifier();
    await notifier.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 0);
    final accountId = notifier.state.accounts.first.id;

    // Inserted oldest-first, on purpose, to prove sort isn't just insertion order.
    await notifier.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 100,
      categoryId: 'cat_food',
      merchant: 'Older Expense',
      date: DateTime(2026, 1, 1),
    );
    await notifier.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 500,
      categoryId: 'cat_transport',
      merchant: 'Newer Expense',
      date: DateTime(2026, 6, 1),
    );

    await tester.pumpWidget(wrapApp(notifier));
    await tester.pumpAndSettle();

    // Default sort: newest first.
    final newerY = tester.getTopLeft(find.text('Newer Expense')).dy;
    final olderY = tester.getTopLeft(find.text('Older Expense')).dy;
    expect(newerY, lessThan(olderY), reason: 'newest transaction should render above older ones by default');

    // Each row shows its category name.
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Transport & Fuel'), findsOneWidget);

    // Switch to "Amount: high to low" — the ₹500 expense should now be first
    // even though it's chronologically newer anyway; add a bigger *older*
    // amount to actually distinguish date-sort from amount-sort.
    await notifier.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 1000,
      categoryId: 'cat_food',
      merchant: 'Big Old Expense',
      date: DateTime(2025, 1, 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount: high to low'));
    await tester.pumpAndSettle();

    final bigOldY = tester.getTopLeft(find.text('Big Old Expense')).dy;
    final newerY2 = tester.getTopLeft(find.text('Newer Expense')).dy;
    expect(bigOldY, lessThan(newerY2), reason: '₹1000 (oldest) must sort above ₹500 under amount-desc');
  });

  testWidgets('category filter narrows the list', (tester) async {
    final notifier = createTestFinanceNotifier();
    await notifier.addAccount(name: 'Wallet', type: AccountType.savingsAccount, openingBalance: 0);
    final accountId = notifier.state.accounts.first.id;

    await notifier.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 100,
      categoryId: 'cat_food',
      merchant: 'Lunch',
      date: DateTime(2026, 1, 1),
    );
    await notifier.addTransaction(
      accountId: accountId,
      type: TransactionType.expense,
      amount: 200,
      categoryId: 'cat_transport',
      merchant: 'Cab Ride',
      date: DateTime(2026, 1, 2),
    );

    await tester.pumpWidget(wrapApp(notifier));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Cab Ride'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Food & Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Cab Ride'), findsNothing);
  });
}
