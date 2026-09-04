import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aspyric/core/theme/app_colors.dart';
import 'package:aspyric/core/theme/app_theme.dart';
import 'package:aspyric/core/theme/palette_scope.dart';

/// Regression guard for the "stale surface after a Light/Dark toggle" bug.
///
/// The module-switcher bar / bottom nav / dashboard body used to keep the
/// previous mode's colours after a theme switch, because they read the static
/// [AppColors] palette and hold no dependency on the animated Material theme
/// (GoRouter keeps them alive in its Navigator). [PaletteScope] — mounted from
/// `MaterialApp.builder` — must force such theme-agnostic descendants to
/// rebuild through the fresh palette on every flip.
class _Host extends StatefulWidget {
  final Widget Function() childBuilder;
  const _Host({super.key, required this.childBuilder});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  ThemeMode mode = ThemeMode.light;
  void setMode(ThemeMode m) => setState(() => mode = m);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) => PaletteScope(mode: mode, child: widget.childBuilder()),
      ),
    );
  }
}

void main() {
  testWidgets('a theme-agnostic child re-reads AppColors on every brightness flip',
      (tester) async {
    final seenBg = <Color>[];

    // This child mirrors a persistent GoRouter screen: it reads the static
    // palette but never depends on Theme.of / themeProvider, so nothing but
    // PaletteScope's re-key can make it rebuild.
    Widget probe() => Builder(
          builder: (_) {
            seenBg.add(AppColors.background);
            return const SizedBox.shrink();
          },
        );

    final hostKey = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: hostKey, childBuilder: probe));
    await tester.pump();

    expect(seenBg, isNotEmpty);
    final lightBg = seenBg.last;
    expect(lightBg, const Color(0xFFF5F7FB), reason: 'light background token');

    // Flip to dark.
    hostKey.currentState!.setMode(ThemeMode.dark);
    await tester.pump();

    expect(seenBg.length, greaterThan(1),
        reason: 'child must rebuild when brightness flips');
    final darkBg = seenBg.last;
    expect(darkBg, const Color(0xFF0A0C10), reason: 'dark background token');
    expect(AppColors.brightness, Brightness.dark);

    // Flip back to light — must return to the light token, not stay dark.
    hostKey.currentState!.setMode(ThemeMode.light);
    await tester.pump();
    expect(seenBg.last, const Color(0xFFF5F7FB));
    expect(AppColors.brightness, Brightness.light);
  });

  testWidgets('every AppColors surface/text token flips with the mode', (tester) async {
    Brightness? at;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return PaletteScope(
              mode: ThemeMode.dark,
              child: Builder(builder: (_) {
                at = AppColors.brightness;
                return const SizedBox.shrink();
              }),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(at, Brightness.dark);

    // Sample a spread of tokens in each mode and assert none is shared across
    // modes (i.e. the whole palette really is mode-dependent).
    List<Color> sample() => [
          AppColors.background,
          AppColors.surface,
          AppColors.surfaceLight,
          AppColors.cardBgElevated,
          AppColors.border,
          AppColors.textPrimary,
          AppColors.textSecondary,
          AppColors.textMuted,
          AppColors.primary,
          AppColors.income,
          AppColors.expense,
          AppColors.transfer,
          AppColors.warning,
          AppColors.info,
        ];

    AppColors.brightness = Brightness.dark;
    final dark = sample();
    AppColors.brightness = Brightness.light;
    final light = sample();

    for (var i = 0; i < dark.length; i++) {
      expect(dark[i], isNot(light[i]), reason: 'token #$i must differ between modes');
    }
  });
}
