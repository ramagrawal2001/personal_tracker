import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_tracker/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Automated End-to-End App Flow Verification', () {
    testWidgets('Verify Complete Application User Journey', (WidgetTester tester) async {
      // 1. Launch Main Application
      await tester.pumpWidget(
        const ProviderScope(
          child: PersonalTrackerApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 2. Verify Login Landing Screen
      expect(find.text('Personal Finance OS'), findsOneWidget);
      expect(find.text('Enter Dashboard as Guest Session'), findsOneWidget);

      // 3. Tap "Enter Dashboard as Guest Session" to authenticate & unlock Dashboard
      final guestButton = find.text('Enter Dashboard as Guest Session');
      await tester.tap(guestButton);
      await tester.pumpAndSettle();

      // 4. Verify Dashboard Screen is displayed
      expect(find.text('FINANCIAL DASHBOARD'), findsOneWidget);
      expect(find.text('NET WORTH'), findsOneWidget);
      expect(find.text('Safe to Spend'), findsOneWidget);

      // 5. Open central Quick Add Modal '+'
      final fabButton = find.byIcon(Icons.add);
      if (fabButton.evaluate().isNotEmpty) {
        await tester.tap(fabButton.first);
        await tester.pumpAndSettle();
      }

      // 6. Dismiss modal if opened
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // 7. Open More Menu
      final moreTab = find.text('More');
      if (moreTab.evaluate().isNotEmpty) {
        await tester.tap(moreTab);
        await tester.pumpAndSettle();
        
        // Verify Financial Modules sheet opens without overflow
        expect(find.text('Financial Modules'), findsOneWidget);
        expect(find.text('Credit Cards'), findsOneWidget);
        expect(find.text('Loans & EMI'), findsOneWidget);
        expect(find.text('Categories'), findsOneWidget);
        expect(find.text('Investments'), findsOneWidget);
      }
    });
  });
}
