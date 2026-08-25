import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
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
  int _notesNavIndex = 0;

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    if (location.startsWith('/notes') && _activeModule != AppModule.notes) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activeModule = AppModule.notes);
      });
    }

    if (_activeModule == AppModule.notes) return _notesNavIndex;

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
        location.startsWith('/more')) {
      return 4;
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    if (_activeModule == AppModule.notes) {
      setState(() => _notesNavIndex = index);
      if (index == 0) context.go('/notes');
      return;
    }
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Financial Modules',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, color: AppColors.textMuted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.15,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildMenuItem(ctx, 'Cards', LucideIcons.creditCard, AppColors.creditCard, () { Navigator.pop(ctx); context.go('/credit-cards'); }),
                        _buildMenuItem(ctx, 'Loans', LucideIcons.landmark, AppColors.loan, () { Navigator.pop(ctx); context.go('/loans'); }),
                        _buildMenuItem(ctx, 'Budgets', LucideIcons.pieChart, AppColors.warning, () { Navigator.pop(ctx); context.go('/budgets'); }),
                        _buildMenuItem(ctx, 'Goals', LucideIcons.target, AppColors.income, () { Navigator.pop(ctx); context.go('/goals'); }),
                        _buildMenuItem(ctx, 'Categories', LucideIcons.tag, AppColors.primary, () { Navigator.pop(ctx); context.go('/categories'); }),
                        _buildMenuItem(ctx, 'Invest', LucideIcons.trendingUp, AppColors.transfer, () { Navigator.pop(ctx); context.go('/investments'); }),
                        _buildMenuItem(ctx, 'Calendar', LucideIcons.calendar, AppColors.accent, () { Navigator.pop(ctx); context.go('/recurring'); }),
                        _buildMenuItem(ctx, 'Reports', LucideIcons.barChart3, AppColors.income, () { Navigator.pop(ctx); context.go('/reports'); }),
                        _buildMenuItem(ctx, 'Net Worth', LucideIcons.wallet, AppColors.transfer, () { Navigator.pop(ctx); context.go('/net-worth'); }),
                        _buildMenuItem(ctx, 'Analytics', LucideIcons.lineChart, AppColors.accent, () { Navigator.pop(ctx); context.go('/analytics'); }),
                        _buildMenuItem(ctx, 'Import', LucideIcons.fileSpreadsheet, AppColors.income, () { Navigator.pop(ctx); CsvImportModal.show(ctx); }),
                        _buildMenuItem(ctx, 'Settings', LucideIcons.settings, AppColors.textSecondary, () { Navigator.pop(ctx); context.go('/settings'); }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: AppDecorations.iconBadge(color, circle: true),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
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
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
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
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context, selectedIndex, isNotes, location),
    );
  }

  Widget? _buildBottomNav(BuildContext context, int selectedIndex, bool isNotes, String location) {
    if (location == '/notes/editor') return null;
    if (location.startsWith('/settings') ||
        location.startsWith('/profile') ||
        location.startsWith('/analytics') ||
        location.startsWith('/ai-assistant')) {
      return null;
    }

    if (isNotes) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _notesNavIndex,
          onTap: (i) => _onItemTapped(i, context),
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.stickyNote), label: 'All Notes'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.pin), label: 'Pinned'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.archive), label: 'Archive'),
          ],
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => _onItemTapped(index, context),
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
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
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

  const _ModuleSwitcherTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 7.5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary.withValues(alpha: 0.45) : AppColors.border,
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
