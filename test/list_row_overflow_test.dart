import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/widgets/app_card.dart';
import 'package:aspyric/core/theme/app_colors.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:aspyric/features/dashboard/presentation/widgets/recent_transactions_widget.dart';
import 'package:aspyric/features/dashboard/presentation/widgets/upcoming_payments_widget.dart';
import 'package:aspyric/features/dashboard/presentation/widgets/safe_to_spend_card.dart';
import 'package:aspyric/features/dashboard/presentation/widgets/net_worth_card.dart';
import 'package:aspyric/features/dashboard/presentation/widgets/money_summary_card.dart';

/// Regression guard for the "long name collides with / pushes off the trailing
/// amount" class of layout bug in list rows (see AccountsScreen's bank-name
/// overflow). Each row widget is pumped at a deliberately narrow 320dp width
/// with an oversized name and a lakh-scale amount, and we assert:
///   (a) nothing throws / no RenderFlex overflow (`tester.takeException()`),
///   (b) the full name string is still present in the tree (ellipsised, not
///       dropped),
///   (c) the amount still renders.
void main() {
  const String longName =
      'kotak Mahindra bank Premium Current Account XYZ';
  const double bigValue = 8372727; // formats to ₹83,72,727
  const String bigAmountFragment = '83,72,727';

  // Headless-safe host: a bare MaterialApp + default ThemeData, the row pinned
  // to 320dp so any unconstrained text block overflows if the fix regresses.
  // No google_fonts / network — every widget under test only reads AppColors
  // constants and the intl-backed CurrencyFormatter.
  Future<void> pumpRow(WidgetTester tester, Widget row) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 320, child: row),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TransactionModel txn() => TransactionModel(
        id: 't1',
        accountId: 'a1',
        type: TransactionType.expense,
        amount: bigValue,
        merchant: longName,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

  RecurringPaymentModel recurring() => RecurringPaymentModel(
        id: 'r1',
        title: longName,
        amount: bigValue,
        frequency: PaymentFrequency.monthly,
        nextDueDate: DateTime(2026, 1, 1),
      );

  testWidgets('AppListTile (accounts row) — long name does not overflow amount',
      (tester) async {
    await pumpRow(
      tester,
      AppListTile(
        icon: Icons.account_balance,
        iconColor: AppColors.primary,
        title: longName,
        subtitle: 'Savings Account •••• 4321',
        trailing: '₹$bigAmountFragment',
        trailingColor: AppColors.income,
        menuButton: const Icon(Icons.more_vert),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('kotak Mahindra bank'), findsOneWidget);
    expect(find.textContaining(bigAmountFragment), findsWidgets);
  });

  testWidgets('RecentTransactionsWidget row — long merchant does not overflow',
      (tester) async {
    await pumpRow(
      tester,
      RecentTransactionsWidget(transactions: [txn()]),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('kotak Mahindra bank'), findsOneWidget);
    expect(find.textContaining(bigAmountFragment), findsWidgets);
  });

  testWidgets('UpcomingPaymentsWidget row — long title does not overflow',
      (tester) async {
    await pumpRow(
      tester,
      UpcomingPaymentsWidget(upcomingPayments: [recurring()]),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('kotak Mahindra bank'), findsOneWidget);
    expect(find.textContaining(bigAmountFragment), findsWidgets);
  });

  testWidgets('SafeToSpendCard header + metrics row do not overflow at 320dp',
      (tester) async {
    await pumpRow(
      tester,
      const SafeToSpendCard(
        safeToSpend: bigValue,
        liquidBalance: bigValue,
        upcomingPayments: bigValue,
        emergencyBuffer: bigValue,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Safe to Spend'), findsOneWidget);
    expect(find.textContaining(bigAmountFragment), findsWidgets);
  });

  testWidgets('NetWorthCard assets/liabilities row does not overflow at 320dp',
      (tester) async {
    await pumpRow(
      tester,
      const NetWorthCard(
        netWorth: bigValue,
        totalAssets: bigValue,
        totalLiabilities: bigValue,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.textContaining(bigAmountFragment), findsWidgets);
  });

  testWidgets('MoneySummaryCard metric + flow rows do not overflow at 320dp',
      (tester) async {
    await pumpRow(
      tester,
      const MoneySummaryCard(
        bankBalance: bigValue,
        creditCardDue: bigValue,
        upcomingEmis: bigValue,
        monthlyIncome: bigValue,
        monthlyExpenses: bigValue,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Bank Balance'), findsOneWidget);
    expect(find.textContaining(bigAmountFragment), findsWidgets);
  });
}
