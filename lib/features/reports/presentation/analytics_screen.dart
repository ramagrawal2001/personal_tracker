import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/models/models.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _touchedPieIndex = -1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeNotifierProvider);

    // Build category spending map (expenses only, current month)
    final now = DateTime.now();
    final monthTxns = state.transactions.where((t) =>
      t.type == TransactionType.expense &&
      t.date.year == now.year &&
      t.date.month == now.month
    ).toList();

    final Map<String, double> catSpend = {};
    for (final t in monthTxns) {
      final cat = t.categoryId ?? 'Uncategorised';
      catSpend[cat] = (catSpend[cat] ?? 0) + t.amount;
    }
    final sortedCats = catSpend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Monthly bar data (last 6 months)
    final List<_MonthBar> monthBars = _buildMonthBars(state.transactions);

    // Top merchants
    final Map<String, double> merchantMap = {};
    for (final t in state.transactions.where((t) => t.type == TransactionType.expense)) {
      final key = t.merchant?.isNotEmpty == true ? t.merchant! : (t.categoryId ?? 'Other');
      merchantMap[key] = (merchantMap[key] ?? 0) + t.amount;
    }
    final topMerchants = (merchantMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6).toList();
    final maxMerchant = topMerchants.isEmpty ? 1.0 : topMerchants.first.value;

    return AppScaffold(
      title: 'Analytics & Insights',
      showBackButton: true,
      bottom: TabBar(
        controller: _tabs,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: const [
          Tab(text: 'Spending'),
          Tab(text: 'Monthly Trends'),
          Tab(text: 'Top Merchants'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Tab 1: Spending donut ──────────────────────────────────────
          _buildSpendingTab(sortedCats, monthTxns, state),
          // ── Tab 2: Monthly bar chart ───────────────────────────────────
          _buildMonthlyTab(monthBars),
          // ── Tab 3: Top merchants ───────────────────────────────────────
          _buildMerchantsTab(topMerchants, maxMerchant),
        ],
      ),
    );
  }

  Widget _buildSpendingTab(List<MapEntry<String, double>> cats, List<dynamic> txns, FinanceState state) {
    final total = cats.fold(0.0, (s, e) => s + e.value);
    final colors = _pieColors();

    if (cats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: EmptyState(
          icon: LucideIcons.pieChart,
          title: 'No expenses this month',
          description: 'Log your transactions to view the interactive category distribution donut chart.',
        ),
      );
    }

    String getCatName(String id) {
      final match = state.categories.where((c) => c.id == id);
      if (match.isNotEmpty) return match.first.name;
      if (id.startsWith('cat_')) {
        return id.substring(4).replaceAll('_', ' ').toUpperCase();
      }
      return id;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Donut chart card
          AppCard(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (evt, resp) {
                          setState(() {
                            _touchedPieIndex = (resp?.touchedSection?.touchedSectionIndex ?? -1);
                          });
                        },
                      ),
                      sectionsSpace: 3,
                      centerSpaceRadius: 65,
                      sections: List.generate(cats.length, (i) {
                        final touched = i == _touchedPieIndex;
                        return PieChartSectionData(
                          value: cats[i].value,
                          color: colors[i % colors.length],
                          radius: touched ? 55 : 45,
                          title: touched ? '${((cats[i].value / total) * 100).toStringAsFixed(1)}%' : '',
                          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        );
                      }),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total Spent', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.format(total),
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Category Breakdown'),
          ...List.generate(cats.length, (i) {
            final pct = total > 0 ? (cats[i].value / total) : 0.0;
            final catName = getCatName(cats[i].key);
            final color = colors[i % colors.length];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 10),
                            Text(catName, style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text(
                          CurrencyFormatter.format(cats[i].value),
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(pct * 100).toStringAsFixed(1)}% of monthly spend',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMonthlyTab(List<_MonthBar> bars) {
    if (bars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: EmptyState(
          icon: LucideIcons.barChart3,
          title: 'No transaction history',
          description: 'Historical monthly income and expense trends will appear here over time.',
        ),
      );
    }
    final maxY = bars.fold(0.0, (m, b) => b.expenses > m ? b.expenses : (b.income > m ? b.income : m));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Income vs Expenses (Last 6 Months)'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
            child: Column(
              children: [
                SizedBox(
                  height: 240,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (maxY > 0 ? maxY : 1000) * 1.2,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, gI, rod, rI) => BarTooltipItem(
                            CurrencyFormatter.format(rod.toY),
                            const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (v, _) => Text(
                              _shortFmt(v),
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i >= 0 && i < bars.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(bars[i].label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(
                        bars.length,
                        (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: bars[i].income,
                              color: AppColors.income,
                              width: 10,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                            BarChartRodData(
                              toY: bars[i].expenses,
                              color: AppColors.expense,
                              width: 10,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _legend('Income', AppColors.income),
                    const SizedBox(width: 24),
                    _legend('Expenses', AppColors.expense),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Monthly Ledger Summaries'),
          ...bars.reversed.take(3).map((b) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(b.label, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('+${CurrencyFormatter.format(b.income)}', style: TextStyle(color: AppColors.income, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('-${CurrencyFormatter.format(b.expenses)}', style: TextStyle(color: AppColors.expense, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildMerchantsTab(List<MapEntry<String, double>> merchants, double maxV) {
    if (merchants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: EmptyState(
          icon: LucideIcons.store,
          title: 'No merchant data',
          description: 'Add merchant details to expenses to discover top spending destinations.',
        ),
      );
    }
    final colors = _pieColors();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Top Spending Merchants & Outlets'),
          ...List.generate(merchants.length, (i) {
            final pct = maxV > 0 ? (merchants[i].value / maxV) : 0.0;
            final color = colors[i % colors.length];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: AppDecorations.iconBadge(color, circle: true),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              merchants[i].key,
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        Text(
                          CurrencyFormatter.format(merchants[i].value),
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) => Row(
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
    ],
  );

  List<_MonthBar> _buildMonthBars(List<TransactionModel> txns) {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final m = DateTime(now.year, now.month - (5 - i));
      final monthTxns = txns.where((t) => t.date.year == m.year && t.date.month == m.month);
      final income = monthTxns.where((t) => t.type == TransactionType.income).fold(0.0, (s, t) => s + t.amount);
      final exp = monthTxns.where((t) => t.type == TransactionType.expense).fold(0.0, (s, t) => s + t.amount);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return _MonthBar(label: months[m.month - 1], income: income, expenses: exp);
    });
  }

  List<Color> _pieColors() => [
    AppColors.primary,
    AppColors.income,
    AppColors.expense,
    AppColors.warning,
    AppColors.accent,
    AppColors.transfer,
    AppColors.creditCard,
    AppColors.loan,
  ];

  String _shortFmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}K' : v.toStringAsFixed(0);
}

class _MonthBar {
  final String label;
  final double income;
  final double expenses;
  const _MonthBar({required this.label, required this.income, required this.expenses});
}
