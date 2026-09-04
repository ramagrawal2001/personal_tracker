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

/// Stands in for `MainShell` + its persistent routed screens: holds a selected
/// tab index and a per-tab scroll position in `State`, reads the static
/// [AppColors] palette, and has NO dependency on `Theme.of` / `themeProvider`.
class _FakeShell extends StatefulWidget {
  const _FakeShell();
  @override
  State<_FakeShell> createState() => _FakeShellState();
}

class _FakeShellState extends State<_FakeShell> {
  static int mountCount = 0;
  static int buildCount = 0;

  int _tab = 0;
  final ScrollController _tab2Scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    mountCount++;
  }

  @override
  void dispose() {
    _tab2Scroll.dispose();
    super.dispose();
  }

  Widget _page(int p, [ScrollController? c]) => ListView.builder(
        controller: c,
        itemCount: 60,
        itemBuilder: (_, i) => SizedBox(
          height: 44,
          child: Text('page-$p item $i',
              style: TextStyle(color: AppColors.textPrimary)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [_page(0), _page(1, _tab2Scroll), _page(2)],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                TextButton(
                  onPressed: () => setState(() => _tab = i),
                  child: Text('Tab ${i + 1}'),
                ),
            ],
          ),
        ],
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

  testWidgets('theme toggle preserves shell tab + scroll State while flipping the palette',
      (tester) async {
    _FakeShellState.mountCount = 0;

    final hostKey = GlobalKey<_HostState>();
    // `const _FakeShell()` -> the SAME widget instance on every PaletteScope
    // rebuild, so nothing but PaletteScope's own in-place rebuild can repaint
    // it, and its State can never be silently remounted by a widget swap.
    await tester.pumpWidget(
      _Host(key: hostKey, childBuilder: () => const _FakeShell()),
    );
    await tester.pumpAndSettle();
    expect(_FakeShellState.mountCount, 1);
    expect(AppColors.brightness, Brightness.light);

    // Move to a non-default tab and scroll its list.
    await tester.tap(find.text('Tab 2'));
    await tester.pumpAndSettle();
    final shell = tester.state<_FakeShellState>(find.byType(_FakeShell));
    shell._tab2Scroll.jumpTo(700);
    await tester.pumpAndSettle();
    expect(shell._tab2Scroll.offset, 700);

    final buildsBefore = _FakeShellState.buildCount;

    // Flip Light -> Dark.
    hostKey.currentState!.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    // Palette actually flipped...
    expect(AppColors.brightness, Brightness.dark);
    // ...the shell repainted in place through the fresh palette...
    expect(_FakeShellState.buildCount, greaterThan(buildsBefore));
    // ...and no State was destroyed: same tab, same scroll offset, no remount.
    expect(_FakeShellState.mountCount, 1, reason: 'State must not be remounted');
    expect(shell._tab, 1, reason: 'selected tab preserved');
    expect(shell._tab2Scroll.offset, 700, reason: 'scroll offset preserved');
  });
}
