import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/presentation/auth_repository.dart';

// ─── Admin analytics provider ─────────────────────────────────────────────────
final adminAnalyticsProvider = FutureProvider<AdminStats>((ref) async {
  final supabase = Supabase.instance.client;

  // Count profiles
  final profilesResp = await supabase.from('profiles').select('id, app_role');
  final profiles = List<Map<String, dynamic>>.from(profilesResp as List);
  final totalUsers = profiles.length;
  final adminCount = profiles.where((p) => p['app_role'] == 'admin').length;

  // Count transactions (aggregate — no sensitive data)
  final txnResp = await supabase.from('transactions').select('id, amount, type');
  final txns = List<Map<String, dynamic>>.from(txnResp as List);
  final totalTxns = txns.length;
  final totalVolume = txns.fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0.0));
  final incomeCount = txns.where((t) => t['type'] == 'income').length;
  final expenseCount = txns.where((t) => t['type'] == 'expense').length;

  return AdminStats(
    totalUsers: totalUsers,
    adminCount: adminCount,
    totalTransactions: totalTxns,
    totalVolume: totalVolume,
    incomeTransactions: incomeCount,
    expenseTransactions: expenseCount,
  );
});

class AdminStats {
  final int totalUsers;
  final int adminCount;
  final int totalTransactions;
  final double totalVolume;
  final int incomeTransactions;
  final int expenseTransactions;

  const AdminStats({
    required this.totalUsers,
    required this.adminCount,
    required this.totalTransactions,
    required this.totalVolume,
    required this.incomeTransactions,
    required this.expenseTransactions,
  });
}

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final analytics = ref.watch(adminAnalyticsProvider);

    // Role check — only admins can access this screen. The router's
    // `/admin` redirect already blocks non-admins from reaching this widget,
    // but this stays as defense-in-depth in case the widget is ever reached
    // another way (e.g. a future deep link that bypasses the redirect).
    final userMeta = authState.user?.userMetadata;
    final appMeta = authState.user?.appMetadata;
    final isAdmin = userMeta?['app_role'] == 'admin' || appMeta?['app_role'] == 'admin';
    if (authState.user == null || !isAdmin) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    return AppScaffold(
      title: 'Control Panel',
      showBackButton: true,
      titleWidget: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.expense.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.expense.withValues(alpha: 0.3)),
            ),
            child: const Text('SUPER ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.expense, letterSpacing: 0.8)),
          ),
          const SizedBox(width: 10),
          const Text('Control Panel', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, color: AppColors.textSecondary, size: 18),
          onPressed: () => ref.refresh(adminAnalyticsProvider),
        ),
      ],
      body: analytics.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, color: AppColors.expense, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to load analytics', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('$err', style: const TextStyle(color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextButton(onPressed: () => ref.refresh(adminAnalyticsProvider), child: const Text('Retry', style: TextStyle(color: AppColors.primary))),
            ],
          ),
        ),
        data: (stats) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Platform Overview'),

              // ── Stats Grid ──────────────────────────────────────────────
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _StatCard(title: 'Total Users', value: '${stats.totalUsers}', icon: LucideIcons.users, color: AppColors.primary),
                  _StatCard(title: 'Admins', value: '${stats.adminCount}', icon: LucideIcons.shieldCheck, color: AppColors.expense),
                  _StatCard(title: 'Transactions', value: '${stats.totalTransactions}', icon: LucideIcons.receipt, color: AppColors.income),
                  _StatCard(title: 'Total Volume', value: '₹${_fmt(stats.totalVolume)}', icon: LucideIcons.indianRupee, color: AppColors.warning),
                ],
              ),
              const SizedBox(height: 24),

              // ── Transaction Breakdown ───────────────────────────────────
              const SectionHeader(title: 'Transaction Breakdown'),
              AppCard(
                child: Column(
                  children: [
                    _BreakdownRow(label: 'Income Transactions', count: stats.incomeTransactions, total: stats.totalTransactions, color: AppColors.income),
                    const SizedBox(height: 14),
                    _BreakdownRow(label: 'Expense Transactions', count: stats.expenseTransactions, total: stats.totalTransactions, color: AppColors.expense),
                    const SizedBox(height: 14),
                    _BreakdownRow(label: 'Other (Transfers etc.)', count: stats.totalTransactions - stats.incomeTransactions - stats.expenseTransactions, total: stats.totalTransactions, color: AppColors.transfer),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── User ratio ─────────────────────────────────────────────
              const SectionHeader(title: 'User Role Distribution'),
              AppCard(
                child: Column(
                  children: [
                    _BreakdownRow(label: 'Standard Users', count: stats.totalUsers - stats.adminCount, total: stats.totalUsers, color: AppColors.primary),
                    const SizedBox(height: 14),
                    _BreakdownRow(label: 'Admins', count: stats.adminCount, total: stats.totalUsers, color: AppColors.expense),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Notice ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppDecorations.alertBanner(AppColors.warning),
                child: const Row(
                  children: [
                    Icon(LucideIcons.info, color: AppColors.warning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Admin view shows only aggregated, anonymised counts. No user-specific financial data is ever displayed here.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: AppDecorations.iconBadge(color, circle: true),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _BreakdownRow({required this.label, required this.count, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.surfaceLight,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 2),
        Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }
}
