import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_tracker/main.dart';

void main() {
  testWidgets('App initializes successfully on Login Screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PersonalTrackerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Personal Finance OS'), findsOneWidget);
  });
}
