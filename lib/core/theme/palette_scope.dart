import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Bridges the non-animated Material theme and the static [AppColors] palette.
///
/// [AppColors] tokens are plain getters read at build time, so a widget that
/// does not itself depend on the theme — notably every screen GoRouter keeps
/// alive inside its persistent `Navigator` — keeps painting the previous mode's
/// colours after a Light/Dark toggle. Mounted from `MaterialApp.builder`, this
/// widget on every build:
///
///  1. Resolves the effective [Brightness] from [mode] + the live platform
///     brightness — NOT from `Theme.of`, so there is no 200ms crossfade lag.
///  2. Writes it to [AppColors.brightness] (the one authoritative writer) and
///     syncs the system status-/navigation-bar icon brightness.
///
/// When the brightness actually flips it then marks every descendant element
/// dirty (see [_rebuildSubtree]) so the whole routed tree repaints through the
/// fresh palette. Crucially this is a rebuild *in place* — no `Element` is
/// swapped — so `MainShell`'s selected bottom-nav tab, every scroll offset and
/// all other `State` survive the toggle. (The previous implementation re-keyed
/// the subtree with a `ValueKey(brightness)`, which rebuilt correctly but
/// destroyed exactly that State.)
class PaletteScope extends StatefulWidget {
  final ThemeMode mode;
  final Widget child;

  const PaletteScope({super.key, required this.mode, required this.child});

  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope> {
  Brightness? _applied;

  @override
  Widget build(BuildContext context) {
    final effective = switch (widget.mode) {
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

    if (_applied != null && _applied != effective) {
      // Brightness flipped. Repaint theme-agnostic descendants (persistent
      // routed screens, MainShell's sub-widgets) without remounting them, so no
      // navigation / scroll State is lost. Deferred to after this frame so we
      // are not marking elements dirty during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildSubtree(context as Element);
      });
    }
    _applied = effective;

    return widget.child;
  }

  static void _rebuildSubtree(Element root) {
    void visit(Element el) {
      el.markNeedsBuild();
      el.visitChildren(visit);
    }

    root.visitChildren(visit);
  }
}
