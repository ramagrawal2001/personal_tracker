import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Bridges the animated Material theme and the static [AppColors] palette.
///
/// [AppColors] tokens are plain getters read at build time, so a widget that
/// does not itself depend on the theme (notably every screen kept alive inside
/// GoRouter's persistent `Navigator`) will keep painting the previous mode's
/// colours after a Light/Dark toggle. This widget, mounted from
/// `MaterialApp.builder`, does three things on every build:
///
///  1. Resolves the effective [Brightness] from [mode] + the live platform
///     brightness — NOT from `Theme.of`, so there is no 200ms crossfade lag.
///  2. Writes it to [AppColors.brightness] (the one authoritative writer) and
///     syncs the system status-/navigation-bar icon brightness.
///  3. Re-keys its subtree on the effective brightness, forcing one clean
///     rebuild of the whole routed tree — theme-agnostic screens included —
///     on every flip.
class PaletteScope extends StatelessWidget {
  final ThemeMode mode;
  final Widget child;

  const PaletteScope({super.key, required this.mode, required this.child});

  @override
  Widget build(BuildContext context) {
    final effective = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    AppColors.brightness = effective;

    final isDark = effective == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return KeyedSubtree(
      key: ValueKey<Brightness>(effective),
      child: child,
    );
  }
}
