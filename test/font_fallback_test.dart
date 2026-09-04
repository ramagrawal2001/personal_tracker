import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:aspyric/core/theme/app_theme.dart';
import 'support/test_bootstrap.dart';

/// Bug 6 regression: the headless / sandboxed test harness has no network, so
/// `AppTheme`'s `GoogleFonts.interTextTheme(...)` must not try to fetch Inter
/// from fonts.gstatic.com. `bootstrapTestEnv()` disables runtime fetching; a
/// themed `MaterialApp` must then build cleanly using the platform font.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bootstrapTestEnv();

  testWidgets('themed MaterialApp builds offline with runtime font fetching disabled',
      (tester) async {
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);

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
  });
}
