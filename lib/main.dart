import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
}

class AspyricApp extends ConsumerWidget {
  const AspyricApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Aspyric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: appRouter,
    );
  }
}
