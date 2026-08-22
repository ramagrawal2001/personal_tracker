import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../transactions/presentation/quick_add_modal.dart';
import '../import_export/presentation/csv_import_modal.dart';


class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location == '/') return 0;
    if (location == '/transactions') return 1;
    if (location == '/accounts') return 3;
    if (location == '/more' ||
        location == '/credit-cards' ||
        location == '/loans' ||
        location == '/budgets' ||
        location == '/recurring' ||
        location == '/reports' ||
        location == '/net-worth' ||
        location == '/settings') {
      return 4;
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/transactions');
        break;
      case 2:
        QuickAddModal.show(context);
        break;
      case 3:
        context.go('/accounts');
        break;
      case 4:
        _showMoreMenu(context);
        break;
    }
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Financial Modules',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMenuItem(ctx, 'Credit Cards', LucideIcons.creditCard, AppColors.creditCard, () {
                    Navigator.pop(ctx);
                    context.go('/credit-cards');
                  }),
                  _buildMenuItem(ctx, 'Loans & EMI', LucideIcons.landmark, AppColors.loan, () {
                    Navigator.pop(ctx);
                    context.go('/loans');
                  }),
                  _buildMenuItem(ctx, 'Budgets', LucideIcons.pieChart, AppColors.warning, () {
                    Navigator.pop(ctx);
                    context.go('/budgets');
                  }),
                  _buildMenuItem(ctx, 'Calendar', LucideIcons.calendar, AppColors.accent, () {
                    Navigator.pop(ctx);
                    context.go('/recurring');
                  }),
                  _buildMenuItem(ctx, 'Reports', LucideIcons.barChart3, AppColors.income, () {
                    Navigator.pop(ctx);
                    context.go('/reports');
                  }),
                  _buildMenuItem(ctx, 'Net Worth', LucideIcons.trendingUp, AppColors.transfer, () {
                    Navigator.pop(ctx);
                    context.go('/net-worth');
                  }),
                  _buildMenuItem(ctx, 'AI Assistant', LucideIcons.bot, AppColors.primary, () {
                    Navigator.pop(ctx);
                    context.go('/ai-assistant');
                  }),
                  _buildMenuItem(ctx, 'CSV Import', LucideIcons.fileSpreadsheet, AppColors.income, () {
                    Navigator.pop(ctx);
                    CsvImportModal.show(ctx);
                  }),
                  _buildMenuItem(ctx, 'Settings', LucideIcons.settings, AppColors.textSecondary, () {
                    Navigator.pop(ctx);
                    context.go('/settings');
                  }),


                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (index) => _onItemTapped(index, context),
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(LucideIcons.layoutDashboard),
              activeIcon: Icon(LucideIcons.layoutDashboard, color: AppColors.primary),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(LucideIcons.receipt),
              activeIcon: Icon(LucideIcons.receipt, color: AppColors.primary),
              label: 'Transactions',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.plus, color: Colors.white, size: 22),
              ),
              label: '',
            ),
            const BottomNavigationBarItem(
              icon: Icon(LucideIcons.wallet),
              activeIcon: Icon(LucideIcons.wallet, color: AppColors.primary),
              label: 'Accounts',
            ),
            const BottomNavigationBarItem(
              icon: Icon(LucideIcons.grid),
              activeIcon: Icon(LucideIcons.grid, color: AppColors.primary),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
