import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/services/notification_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Route Flutter framework errors (widget build/layout/paint errors)
    // through the same reporting path instead of only the red-screen.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    // Catch errors from platform channels / native callbacks that don't flow
    // through the Flutter framework's own error zone.
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher error: $error\n$stack');
      return true;
    };

    try {
      await SupabaseService.initialize();
    } catch (e) {
      debugPrint('Supabase initialization fallback: $e');
    }
    try {
      await NotificationService.init();
    } catch (e) {
      debugPrint('Notification initialization fallback: $e');
    }

    runApp(
      const ProviderScope(
        child: AspyricApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
  });
}

class AspyricApp extends ConsumerWidget {
  const AspyricApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Aspyric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    );
  }
}
