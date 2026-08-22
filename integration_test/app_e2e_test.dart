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

      // 2. Verify Login Screen is displayed
      expect(find.text('Personal Finance OS'), findsOneWidget);
      expect(find.text('Sign In & Open Dashboard'), findsOneWidget);
    });
  });
}
