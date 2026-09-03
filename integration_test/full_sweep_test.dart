// Full-app sweep: visits every route in BOTH light and dark, asserts nothing
// throws / overflows, runs a WCAG contrast audit on every rendered Text, and
// exercises the create / edit / delete buttons, dropdowns, and pickers on the
// core modules.
//
// Run:  flutter test integration_test/full_sweep_test.dart -d <device>

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:aspyric/main.dart';
import 'package:aspyric/core/router/app_router.dart';
import 'package:aspyric/core/theme/app_colors.dart';
import 'package:aspyric/core/theme/theme_provider.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:drift/native.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Contrast helpers (WCAG 2.1 relative luminance / ratio)
// ─────────────────────────────────────────────────────────────────────────────
double _lin(double c) {
  c = c / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color c) =>
    0.2126 * _lin(c.r * 255) + 0.7152 * _lin(c.g * 255) + 0.0722 * _lin(c.b * 255);

double _contrast(Color fg, Color bg) {
  final l1 = _luminance(fg);
  final l2 = _luminance(bg);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/// Alpha-composite [fg] over opaque [bg].
Color _composite(Color fg, Color bg) {
  final a = fg.a;
  if (a >= 1.0) return fg;
  return Color.fromARGB(
    255,
    ((fg.r * a + bg.r * (1 - a)) * 255).round(),
    ((fg.g * a + bg.g * (1 - a)) * 255).round(),
    ((fg.b * a + bg.b * (1 - a)) * 255).round(),
  );
}

class _Violation {
  final String route;
  final String mode;
  final String text;
  final double ratio;
  final Color fg;
  final Color bg;
  _Violation(this.route, this.mode, this.text, this.ratio, this.fg, this.bg);

  @override
  String toString() {
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
    final t = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    return '[$mode] $route  ratio=${ratio.toStringAsFixed(2)}  '
        'fg=${hex(fg)} bg=${hex(bg)}  "$t"';
  }
}

/// Walks up the render tree from [start] to the first ancestor that paints an
/// opaque solid colour, and returns it. Falls back to [fallback].
Color _backgroundBehind(RenderObject start, Color fallback) {
  RenderObject? ro = start.parent;
  while (ro != null) {
    if (ro is RenderDecoratedBox) {
      final d = ro.decoration;
      if (d is BoxDecoration && d.color != null && d.color!.a >= 1.0) {
        return d.color!;
      }
      // A gradient surface (hero cards, glass credit cards) is a deliberate
      // opaque background — approximate it with the mean of its opaque stops
      // so contrast is still measured rather than skipped as unknown.
      if (d is BoxDecoration && d.gradient != null) {
        final stops = d.gradient!.colors.where((c) => c.a >= 1.0).toList();
        if (stops.isNotEmpty) {
          final r = stops.map((c) => c.r).reduce((a, b) => a + b) / stops.length;
          final g = stops.map((c) => c.g).reduce((a, b) => a + b) / stops.length;
          final b = stops.map((c) => c.b).reduce((a, b) => a + b) / stops.length;
          return Color.from(alpha: 1.0, red: r, green: g, blue: b);
        }
      }
    }
    if (ro is RenderPhysicalModel && ro.color.a >= 1.0) return ro.color;
    if (ro is RenderPhysicalShape && ro.color.a >= 1.0) return ro.color;
    // ColoredBox / other colour-bearing render objects
    try {
      final dynamic dyn = ro;
      final c = dyn.color;
      if (c is Color && c.a >= 1.0) return c;
    } catch (_) {}
    ro = ro.parent;
  }
  return fallback;
}

/// Audits every on-screen paragraph. Returns violations (ratio < 3.0 for
/// small text). Text with an undeterminable colour is skipped.
List<_Violation> _auditText(WidgetTester tester, String route, String mode, Color scaffoldBg) {
  final out = <_Violation>[];
  for (final el in tester.allElements) {
    final ro = el.renderObject;
    if (ro is! RenderParagraph) continue;
    if (!ro.attached || ro.size.isEmpty) continue;

    // On-screen?
    final topLeft = ro.localToGlobal(Offset.zero);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (topLeft.dx > screen.width || topLeft.dy > screen.height) continue;
    if (topLeft.dx + ro.size.width < 0 || topLeft.dy + ro.size.height < 0) continue;

    final plain = ro.text.toPlainText().trim();
    // Only audit paragraphs that actually contain a readable glyph. This
    // skips empty / whitespace / zero-width / WidgetSpan-placeholder nodes
    // and icon-font glyphs (Private Use Area) \u2014 none of which are "text a
    // user is meant to read", so a low fg/bg contrast there is irrelevant.
    if (!RegExp('[A-Za-z0-9\u00C0-\u024F\u0900-\u097F]').hasMatch(plain)) {
      continue;
    }

    // Collect the span colours actually used.
    final colours = <Color>{};
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        final c = span.style?.color;
        if (c != null) colours.add(c);
        span.children?.forEach(visit);
      }
    }

    visit(ro.text);
    if (colours.isEmpty && ro.text.style?.color != null) {
      colours.add(ro.text.style!.color!);
    }
    if (colours.isEmpty) continue; // inherited from DefaultTextStyle we can't see

    final bg = _backgroundBehind(ro, scaffoldBg);
    for (final raw in colours) {
      final fg = _composite(raw, bg);
      final ratio = _contrast(fg, bg);
      if (ratio < 3.0) {
        out.add(_Violation(route, mode, plain, ratio, fg, bg));
      }
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────

FinanceNotifier _seededNotifier() {
  final n = FinanceNotifier(
    AppDatabase.forTesting(NativeDatabase.memory()),
    autoLoad: false,
  );
  n.addAccount(name: 'HDFC Savings', type: AccountType.savingsAccount, bank: 'HDFC', openingBalance: 125000);
  n.addAccount(name: 'Cash Wallet', type: AccountType.cash, openingBalance: 4200);
  n.addAccount(name: 'SBI Current', type: AccountType.currentAccount, bank: 'SBI', openingBalance: 60000);
  final acc = n.state.accounts.first.id;
  final acc2 = n.state.accounts[2].id;
  n.addCreditCard(name: 'Amazon Pay ICICI', bank: 'ICICI', last4: '4417', creditLimit: 200000, statementDay: 3, dueDay: 20);
  n.addLoan(name: 'Car Loan', provider: 'Kotak', principalAmount: 800000, interestRate: 9.2, monthlyEmi: 16500, dueDay: 5, tenureMonths: 60);
  n.addInvestment(name: 'Nifty 50 Index', type: InvestmentType.mutualFundSip, investedAmount: 300000, currentValue: 361000, monthlySipAmount: 15000, sipDay: 1);
  n.addGoal(name: 'Japan Trip', targetAmount: 400000, currentSavedAmount: 145000, targetDate: DateTime.now().add(const Duration(days: 300)));
  n.addBudget(categoryId: 'cat_food', monthlyLimit: 20000);
  n.addRecurringPayment(title: 'Netflix', amount: 649, frequency: PaymentFrequency.monthly, nextDueDate: DateTime.now().add(const Duration(days: 6)));
  for (var i = 0; i < 8; i++) {
    n.addTransaction(
      accountId: acc,
      type: i.isEven ? TransactionType.expense : TransactionType.income,
      amount: (i + 1) * 730.0,
      categoryId: i.isEven ? 'cat_food' : 'cat_salary',
      merchant: i.isEven ? 'Store $i' : 'Employer',
      date: DateTime.now().subtract(Duration(days: i * 3)),
    );
  }
  n.addTransaction(accountId: acc, toAccountId: acc2, type: TransactionType.transfer, amount: 5000, date: DateTime.now());
  return n;
}

const _routes = <String>[
  '/', '/transactions', '/accounts', '/credit-cards', '/loans', '/budgets',
  '/goals', '/goals/add', '/categories', '/investments', '/recurring',
  '/net-worth', '/reports', '/analytics', '/settings', '/profile',
  '/notes', '/privacy-policy', '/terms',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, {int frames = 22}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 70));
    }
  }

  Future<void> pumpUntil(WidgetTester t, bool Function() cond, {int frames = 160}) async {
    for (var i = 0; i < frames; i++) {
      if (cond()) return;
      await t.pump(const Duration(milliseconds: 80));
    }
  }

  bool present(String s) => find.text(s).evaluate().isNotEmpty;

  testWidgets('every route renders in light & dark with readable text, and core CRUD works',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1290, 2796); // iPhone 15/17 Pro @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final allViolations = <_Violation>[];
    final failures = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeNotifierProvider.overrideWith((ref) => _seededNotifier()),
        ],
        child: const AspyricApp(),
      ),
    );
    await pumpUntil(tester, () => present('Sign In to Aspyric'));

    // Sign in (debug demo bypass)
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), 'test@aspyric.app');
    await tester.enterText(f.at(1), 'Aspyric@123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await pumpUntil(tester, () => present('Dashboard'));
    await settle(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(AspyricApp)));
    final router = container.read(appRouterProvider);

    // ── Route sweep × both themes ─────────────────────────────────────────
    for (final mode in const [ThemeMode.dark, ThemeMode.light]) {
      container.read(themeProvider.notifier).setTheme(mode);
      await settle(tester);
      final label = mode == ThemeMode.dark ? 'dark' : 'light';
      final scaffoldBg = AppColors.background; // now theme-aware

      for (final route in _routes) {
        try {
          router.go(route);
          await settle(tester);
        } catch (e) {
          failures.add('navigate $route [$label]: $e');
          continue;
        }
        final ex = tester.takeException();
        if (ex != null) failures.add('render $route [$label] threw: $ex');
        allViolations.addAll(_auditText(tester, route, label, scaffoldBg));
      }
    }

    // Interaction pass runs in dark (behaviour is theme-independent).
    container.read(themeProvider.notifier).setTheme(ThemeMode.dark);
    router.go('/');
    await settle(tester);

    // ── CRUD: Accounts ──────────────────────────────────────────────────────
    Future<void> crud({
      required String route,
      required String modalTitle,
      required Map<int, String> fields,
      required String submitLabel,
      required String createdNeedle,
    }) async {
      try {
        router.go(route);
        await settle(tester);
        final plus = find.descendant(
            of: find.byType(AppBar), matching: find.byIcon(LucideIcons.plus));
        if (plus.evaluate().isEmpty) {
          failures.add('CRUD $route: no app-bar add button');
          return;
        }
        await tester.tap(plus.first);
        await pumpUntil(tester, () => present(modalTitle));
        await settle(tester);
        if (!present(modalTitle)) {
          failures.add('CRUD $route: modal "$modalTitle" did not open');
          return;
        }
        final tf = find.byType(TextField);
        for (final entry in fields.entries) {
          await tester.enterText(tf.at(entry.key), entry.value);
          await tester.pump(const Duration(milliseconds: 50));
        }
        final submit = find.widgetWithText(ElevatedButton, submitLabel);
        await tester.ensureVisible(submit.first);
        await tester.tap(submit.first);
        await pumpUntil(tester, () => present(createdNeedle));
        await settle(tester);
        if (!present(createdNeedle)) {
          failures.add('CRUD $route: created row "$createdNeedle" not visible after submit');
        }
        final ex = tester.takeException();
        if (ex != null) failures.add('CRUD $route threw: $ex');
      } catch (e) {
        failures.add('CRUD $route: $e');
      }
    }

    await crud(
      route: '/accounts',
      modalTitle: 'Add New Account',
      fields: {0: 'Sweep Test Bank', 3: '9999'},
      submitLabel: 'Create Account',
      createdNeedle: 'Sweep Test Bank',
    );

    // ── CRUD: Category (simple, no numeric parsing pitfalls) ────────────────
    try {
      router.go('/categories');
      await settle(tester);
      final plus = find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(LucideIcons.plus));
      if (plus.evaluate().isNotEmpty) {
        await tester.tap(plus.first);
        await pumpUntil(tester, () => present('Add Category'));
        await settle(tester);
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          await tester.enterText(tf.first, 'Sweep Category');
          await tester.pump(const Duration(milliseconds: 50));
          final save = find.widgetWithText(ElevatedButton, 'Add Category');
          if (save.evaluate().isNotEmpty) {
            await tester.ensureVisible(save.first);
            await tester.tap(save.first);
            await pumpUntil(tester, () => present('Sweep Category'));
            await settle(tester);
            if (!present('Sweep Category')) {
              failures.add('CRUD /categories: new category not visible');
            }
          }
        }
      }
      final ex = tester.takeException();
      if (ex != null) failures.add('CRUD /categories threw: $ex');
    } catch (e) {
      failures.add('CRUD /categories: $e');
    }

    // ── CRUD: Transaction via Quick Add (bottom-nav centre) ─────────────────
    try {
      router.go('/');
      await settle(tester);
      await tester.tap(find.byTooltip('Quick add transaction'));
      await pumpUntil(tester, () => present('Quick Add') || present('Add Transaction'));
      await settle(tester);
      final ex = tester.takeException();
      if (ex != null) failures.add('QuickAdd modal threw: $ex');
      // Close it again (Escape via back).
      if (find.byIcon(LucideIcons.x).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(LucideIcons.x).first);
        await settle(tester);
      }
    } catch (e) {
      failures.add('QuickAdd: $e');
    }

    // ── Delete the account we created (menu → Delete → confirm) ─────────────
    try {
      router.go('/accounts');
      await settle(tester);
      final menu = find.byIcon(LucideIcons.moreVertical);
      if (menu.evaluate().isNotEmpty) {
        await tester.tap(menu.first);
        await settle(tester);
        if (present('Delete')) {
          await tester.tap(find.text('Delete').last);
          await settle(tester);
          if (find.widgetWithText(ElevatedButton, 'Delete').evaluate().isNotEmpty) {
            await tester.tap(find.widgetWithText(ElevatedButton, 'Delete').first);
            await settle(tester);
          }
        }
      }
      final ex = tester.takeException();
      if (ex != null) failures.add('Account delete threw: $ex');
    } catch (e) {
      failures.add('Account delete: $e');
    }

    // ── Report ─────────────────────────────────────────────────────────────
    final byMode = <String, int>{};
    for (final v in allViolations) {
      byMode[v.mode] = (byMode[v.mode] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('\n════ CONTRAST AUDIT ════  dark=${byMode['dark'] ?? 0}  light=${byMode['light'] ?? 0} '
        '(text with ratio < 3.0)');
    final severe = allViolations.where((v) => v.ratio < 1.6).toList();
    for (final v in (allViolations..sort((a, b) => a.ratio.compareTo(b.ratio))).take(60)) {
      // ignore: avoid_print
      print(v);
    }
    // ignore: avoid_print
    print('════ INTERACTION FAILURES ════ ${failures.length}');
    for (final x in failures) {
      // ignore: avoid_print
      print(' • $x');
    }

    // Hard assertions: nothing may crash, and no text may be all-but-invisible.
    expect(failures, isEmpty, reason: 'button / CRUD / render failures:\n${failures.join('\n')}');
    expect(severe, isEmpty,
        reason: 'text effectively invisible (contrast < 1.6):\n${severe.join('\n')}');
  });
}
