import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_tracker/main.dart';

void main() {
  testWidgets('App initializes successfully on Splash Screen and navigates to Login Screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PersonalTrackerApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Personal Finance OS'), findsOneWidget);

    // Pump timer to complete splash navigation
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Personal Finance OS'), findsWidgets);
  });
}
