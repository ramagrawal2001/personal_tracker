import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
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
  void dispose() { _tabs.dispose(); super.dispose(); }

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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('ANALYTICS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Spending'),
            Tab(text: 'Monthly'),
            Tab(text: 'Merchants'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Tab 1: Spending donut ──────────────────────────────────────
          _buildSpendingTab(sortedCats, monthTxns),
          // ── Tab 2: Monthly bar chart ───────────────────────────────────
          _buildMonthlyTab(monthBars),
          // ── Tab 3: Top merchants ───────────────────────────────────────
          _buildMerchantsTab(topMerchants, maxMerchant),
        ],
      ),
    );
  }

  Widget _buildSpendingTab(List<MapEntry<String, double>> cats, List<dynamic> txns) {
    final total = cats.fold(0.0, (s, e) => s + e.value);
    final colors = _pieColors();

    if (cats.isEmpty) return _emptyState('No expenses this month', LucideIcons.pieChart);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Donut chart
          SizedBox(
            height: 240,
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
                    centerSpaceRadius: 70,
                    sections: List.generate(cats.length, (i) {
                      final touched = i == _touchedPieIndex;
                      return PieChartSectionData(
                        value: cats[i].value,
                        color: colors[i % colors.length],
                        radius: touched ? 60 : 50,
                        title: touched ? '${((cats[i].value / total) * 100).toStringAsFixed(1)}%' : '',
                        titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      );
                    }),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Total', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text('₹${_fmt(total)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('BY CATEGORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...List.generate(cats.length, (i) {
            final pct = total > 0 ? (cats[i].value / total) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(cats[i].key, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                      Text('₹${_fmt(cats[i].value)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: AlwaysStoppedAnimation(colors[i % colors.length]),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMonthlyTab(List<_MonthBar> bars) {
    if (bars.isEmpty) return _emptyState('No transaction history', LucideIcons.barChart3);
    final maxY = bars.fold(0.0, (m, b) => b.expenses > m ? b.expenses : m);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('INCOME vs EXPENSES — LAST 6 MONTHS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 24),
          SizedBox(
            height: 280,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gI, rod, rI) => BarTooltipItem(
                      '₹${_fmt(rod.toY)}',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, _) => Text('₹${_shortFmt(v)}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i >= 0 && i < bars.length) return Padding(padding: const EdgeInsets.only(top: 6), child: Text(bars[i].label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)));
                    return const Text('');
                  })),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5)),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(bars.length, (i) => BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(toY: bars[i].income, color: AppColors.income.withValues(alpha: 0.8), width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                    BarChartRodData(toY: bars[i].expenses, color: AppColors.expense.withValues(alpha: 0.8), width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  ],
                )),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend('Income', AppColors.income),
              const SizedBox(width: 24),
              _legend('Expenses', AppColors.expense),
            ],
          ),
          const SizedBox(height: 24),
          const Text('MONTH SUMMARY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...bars.reversed.take(3).map((b) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(b.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('In: ₹${_fmt(b.income)}', style: const TextStyle(color: AppColors.income, fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('Out: ₹${_fmt(b.expenses)}', style: const TextStyle(color: AppColors.expense, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildMerchantsTab(List<MapEntry<String, double>> merchants, double maxV) {
    if (merchants.isEmpty) return _emptyState('No merchant data', LucideIcons.store);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOP SPENDING MERCHANTS / CATEGORIES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 16),
          ...List.generate(merchants.length, (i) {
            final pct = merchants[i].value / maxV;
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: _pieColors()[i % _pieColors().length].withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text('${i + 1}', style: TextStyle(color: _pieColors()[i % _pieColors().length], fontWeight: FontWeight.bold, fontSize: 14))),
                        ),
                        const SizedBox(width: 10),
                        Text(merchants[i].key, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                      ]),
                      Text('₹${_fmt(merchants[i].value)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: AlwaysStoppedAnimation(_pieColors()[i % _pieColors().length]),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _emptyState(String msg, IconData icon) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text(msg, style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
      ],
    ),
  );

  Widget _legend(String label, Color color) => Row(children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
  ]);

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

  List<Color> _pieColors() => [AppColors.primary, AppColors.income, AppColors.expense, AppColors.warning, AppColors.accent, AppColors.transfer, AppColors.creditCard, AppColors.loan];
  String _fmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.toStringAsFixed(0);
  String _shortFmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}K' : v.toStringAsFixed(0);
}

class _MonthBar { final String label; final double income; final double expenses; const _MonthBar({required this.label, required this.income, required this.expenses}); }
