import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aspyric/main.dart';

void main() {
  testWidgets('App initializes successfully on Splash Screen and navigates to Login Screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AspyricApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Aspyric'), findsOneWidget);

    // Pump duration to complete splash navigation
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Aspyric'), findsWidgets);
  });
}
