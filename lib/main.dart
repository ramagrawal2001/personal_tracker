import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/palette_scope.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/services/notification_service.dart';
import 'core/sync/sync_service.dart';

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

    // Seed the ambient palette brightness ONCE, before the first frame paints,
    // from the persisted theme mode (falling back to the platform brightness
    // for System). After this, `MaterialApp.builder` is the single
    // authoritative writer of `AppColors.brightness`.
    try {
      final prefs = await SharedPreferences.getInstance();
      // Key mirrors `_kThemeKey` in core/theme/theme_provider.dart.
      final saved = prefs.getString('app_theme_mode');
      AppColors.brightness = switch (saved) {
        'light' => Brightness.light,
        'dark' => Brightness.dark,
        _ => PlatformDispatcher.instance.platformBrightness,
      };
    } catch (_) {/* keep the default */}

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
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(appRouterProvider);

    // Eagerly instantiate the sync service so it attaches its auth listener
    // and starts draining the outbox once a session exists.
    ref.watch(syncServiceProvider);

    return MaterialApp.router(
      title: 'Aspyric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Hard cut on theme change. `AppColors` is a static palette read at build
      // time, so a 200ms `AnimatedTheme` crossfade would leave `Theme.of` (and
      // therefore the palette) reporting the OLD brightness for the first
      // ~100ms after a toggle — the "stale surface" bug. A zero-duration swap
      // keeps the palette, the Material theme and the forced subtree rebuild
      // below all in lock-step on a single frame.
      themeAnimationDuration: Duration.zero,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      builder: (context, child) => PaletteScope(
        mode: themeMode,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
