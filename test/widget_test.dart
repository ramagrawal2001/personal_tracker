import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_tracker/main.dart';

void main() {
  testWidgets('App initializes successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PersonalTrackerApp(),
      ),
    );
    expect(find.text('FINANCIAL DASHBOARD'), findsOneWidget);
  });
}
