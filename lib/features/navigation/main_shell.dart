import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../transactions/presentation/quick_add_modal.dart';
import '../import_export/presentation/csv_import_modal.dart';

enum AppModule { finance, notes }

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppModule _activeModule = AppModule.finance;

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    // Auto-switch module based on path
    if (location.startsWith('/notes') && _activeModule != AppModule.notes) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activeModule = AppModule.notes);
      });
    } else if (!location.startsWith('/notes') && !location.startsWith('/ai-assistant')
        && _activeModule == AppModule.notes && !location.startsWith('/notes')) {
      // stay — handled by _switchModule
    }

    if (_activeModule == AppModule.notes) return 0;

    if (location == '/') return 0;
    if (location == '/transactions') return 1;
    if (location == '/accounts') return 3;
    if (location.startsWith('/credit-cards') ||
        location.startsWith('/loans') ||
        location.startsWith('/budgets') ||
        location.startsWith('/recurring') ||
        location.startsWith('/reports') ||
        location.startsWith('/net-worth') ||
        location.startsWith('/analytics') ||
        location.startsWith('/settings') ||
        location.startsWith('/profile') ||
        location.startsWith('/ai-assistant') ||
        location.startsWith('/more')) { return 4; }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    if (_activeModule == AppModule.notes) {
      if (index == 0) context.go('/notes');
      return;
    }
    switch (index) {
      case 0: context.go('/'); break;
      case 1: context.go('/transactions'); break;
      case 2: QuickAddModal.show(context); break;
      case 3: context.go('/accounts'); break;
      case 4: _showMoreMenu(context); break;
    }
  }

  void _switchModule(AppModule module) {
    setState(() => _activeModule = module);
    if (module == AppModule.notes) {
      context.go('/notes');
    } else {
      context.go('/');
    }
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  const Text('Financial Modules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      IconButton(icon: const Icon(LucideIcons.x, color: AppColors.textMuted), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.2,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildMenuItem(ctx, 'Cards Vault', LucideIcons.creditCard, AppColors.creditCard, () { Navigator.pop(ctx); context.go('/credit-cards'); }),
                      _buildMenuItem(ctx, 'Loans & EMI', LucideIcons.landmark, AppColors.loan, () { Navigator.pop(ctx); context.go('/loans'); }),
                      _buildMenuItem(ctx, 'Budgets', LucideIcons.pieChart, AppColors.warning, () { Navigator.pop(ctx); context.go('/budgets'); }),
                      _buildMenuItem(ctx, 'Savings Goals', LucideIcons.target, AppColors.income, () { Navigator.pop(ctx); context.go('/goals'); }),
                      _buildMenuItem(ctx, 'Categories', LucideIcons.tag, AppColors.primary, () { Navigator.pop(ctx); context.go('/categories'); }),
                      _buildMenuItem(ctx, 'Investments', LucideIcons.trendingUp, AppColors.transfer, () { Navigator.pop(ctx); context.go('/investments'); }),
                      _buildMenuItem(ctx, 'Calendar', LucideIcons.calendar, AppColors.accent, () { Navigator.pop(ctx); context.go('/recurring'); }),
                      _buildMenuItem(ctx, 'Reports', LucideIcons.barChart3, AppColors.income, () { Navigator.pop(ctx); context.go('/reports'); }),
                      _buildMenuItem(ctx, 'Net Worth', LucideIcons.trendingUp, AppColors.transfer, () { Navigator.pop(ctx); context.go('/net-worth'); }),
                      _buildMenuItem(ctx, 'Analytics', LucideIcons.pieChart, AppColors.accent, () { Navigator.pop(ctx); context.go('/analytics'); }),
                      _buildMenuItem(ctx, 'AI Assistant', LucideIcons.bot, AppColors.primary, () { Navigator.pop(ctx); context.go('/ai-assistant'); }),
                      _buildMenuItem(ctx, 'CSV Import', LucideIcons.fileSpreadsheet, AppColors.income, () { Navigator.pop(ctx); CsvImportModal.show(ctx); }),
                      _buildMenuItem(ctx, 'Settings', LucideIcons.settings, AppColors.textSecondary, () { Navigator.pop(ctx); context.go('/settings'); }),
                    ],
                  ),
                ],
              ),
            ),
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
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);
    final isNotes = _activeModule == AppModule.notes;
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      body: Column(
        children: [
          // ── Module Switcher Bar ──────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ModuleSwitcherTab(
                      label: AppLocalizations.of(context).home,
                      icon: LucideIcons.trendingUp,
                      selected: !isNotes,
                      onTap: () => _switchModule(AppModule.finance),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModuleSwitcherTab(
                      label: AppLocalizations.of(context).notes,
                      icon: LucideIcons.stickyNote,
                      selected: isNotes,
                      onTap: () => _switchModule(AppModule.notes),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // ── Page Content ─────────────────────────────────────────────────
          Expanded(child: widget.child),
        ],
      ),
      // ── Bottom Nav ──────────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(context, selectedIndex, isNotes, location),
    );
  }

  Widget? _buildBottomNav(BuildContext context, int selectedIndex, bool isNotes, String location) {
    if (location == '/notes/editor') return null;
    if (location.startsWith('/settings') || location.startsWith('/profile') ||
        location.startsWith('/analytics') || location.startsWith('/ai-assistant')) return null;

    if (isNotes) {
      return Container(
        decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border, width: 1))),
        child: BottomNavigationBar(
          currentIndex: 0,
          onTap: (i) => _onItemTapped(i, context),
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.stickyNote), label: 'All Notes'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.pin), label: 'Pinned'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.archive), label: 'Archive'),
          ],
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border, width: 1))),
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
          BottomNavigationBarItem(
            icon: const Icon(LucideIcons.layoutDashboard),
            activeIcon: const Icon(LucideIcons.layoutDashboard, color: AppColors.primary),
            label: AppLocalizations.of(context).home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(LucideIcons.receipt),
            activeIcon: const Icon(LucideIcons.receipt, color: AppColors.primary),
            label: AppLocalizations.of(context).transactions,
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Icon(LucideIcons.plus, color: Colors.white, size: 22),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: const Icon(LucideIcons.wallet),
            activeIcon: const Icon(LucideIcons.wallet, color: AppColors.primary),
            label: AppLocalizations.of(context).accounts,
          ),
          BottomNavigationBarItem(
            icon: const Icon(LucideIcons.grid),
            activeIcon: const Icon(LucideIcons.grid, color: AppColors.primary),
            label: AppLocalizations.of(context).more,
          ),
        ],
      ),
    );
  }
}

class _ModuleSwitcherTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModuleSwitcherTab({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
