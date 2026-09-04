import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aspyric/core/theme/app_theme.dart';
import 'support/test_bootstrap.dart';

/// Bug 6 regression: `AppTheme` must build cleanly with no network — Inter is
/// bundled locally (assets/fonts/Inter-Variable.ttf), not fetched at runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bootstrapTestEnv();

  testWidgets('themed MaterialApp builds offline using the bundled Inter font',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: Center(child: Text('hermetic'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('hermetic'), findsOneWidget);
    // bodyMedium is what a bare Text() resolves through by default.
    final resolvedFamily =
        Theme.of(tester.element(find.text('hermetic'))).textTheme.bodyMedium?.fontFamily;
    expect(resolvedFamily, 'Inter');
  });
}
