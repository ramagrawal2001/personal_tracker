import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/presentation/auth_repository.dart';
import '../../../core/services/biometric_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifEnabled = false;
  int _notifHour = 21;
  int _notifMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifState();
  }

  Future<void> _loadNotifState() async {
    final enabled = await NotificationService.isEnabled();
    final hour = await NotificationService.getReminderHour();
    final min = await NotificationService.getReminderMinute();
    if (mounted) setState(() { _notifEnabled = enabled; _notifHour = hour; _notifMinute = min; });
  }

  Future<void> _toggleNotifications(bool val) async {
    if (val) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification permission denied'), backgroundColor: AppColors.expense, behavior: SnackBarBehavior.floating),
        );
        return;
      }
      await NotificationService.scheduleDailyReminder(hour: _notifHour, minute: _notifMinute);
    } else {
      await NotificationService.cancelReminder();
    }
    setState(() => _notifEnabled = val);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _notifHour, minute: _notifMinute));
    if (picked != null) {
      setState(() { _notifHour = picked.hour; _notifMinute = picked.minute; });
      if (_notifEnabled) {
        await NotificationService.scheduleDailyReminder(hour: picked.hour, minute: picked.minute);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final financeNotifier = ref.read(financeNotifierProvider.notifier);
    final locale = ref.watch(localeProvider);

    return AppScaffold(
      title: 'Settings & Preferences',
      showBackButton: true,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Account ───────────────────────────────────────────────────
          const SectionLabel(label: 'Account'),
          Consumer(builder: (context, ref, _) {
            final user = ref.watch(authNotifierProvider).user;
            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: AppDecorations.iconBadge(AppColors.primary, circle: true),
                  child: const Icon(LucideIcons.user, color: AppColors.primary, size: 20),
                ),
                title: Text(user?.email ?? 'Not signed in', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: const Text('Local Encrypted & Cloud Synced', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
                onTap: () => context.go('/profile'),
              ),
            );
          }),
          const SizedBox(height: 18),

          // ── Appearance ───────────────────────────────────────────────
          const SectionLabel(label: 'Appearance & Theme'),
          AppCard(
            child: Row(
              children: [
                const Icon(LucideIcons.moon, color: AppColors.primary, size: 18),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Dark theme', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text('Always on', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Language ─────────────────────────────────────────────────
          const SectionLabel(label: 'Language & Locale'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Application Language', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _LangChip('EN', 'English', const Locale('en'), locale, (l) => ref.read(localeProvider.notifier).setLocale(l)),
                    _LangChip('हिं', 'Hindi', const Locale('hi'), locale, (l) => ref.read(localeProvider.notifier).setLocale(l)),
                    _LangChip('म', 'Marathi', const Locale('mr'), locale, (l) => ref.read(localeProvider.notifier).setLocale(l)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Currency & Region ─────────────────────────────────────────
          const SectionLabel(label: 'Currency & Region'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Currency Symbol', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CurrencyChip('₹', 'INR', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip(r'$', 'USD', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('€', 'EUR', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('£', 'GBP', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('¥', 'JPY', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('₩', 'KRW', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('₺', 'TRY', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('₴', 'UAH', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('৳', 'BDT', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('₦', 'NGN', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('﷼', 'SAR', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('Fr', 'CHF', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('A\$', 'AUD', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('C\$', 'CAD', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('RM', 'MYR', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                    _CurrencyChip('฿', 'THB', financeState.currencySymbol, financeNotifier.setCurrencySymbol),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.eye, color: AppColors.textMuted, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Preview: ${CurrencyFormatter.format(100000)} • ${CurrencyFormatter.format(25499.50, showDecimals: true)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Notifications ──────────────────────────────────────────────
          const SectionLabel(label: 'Notifications'),
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.warning),
                    child: const Icon(LucideIcons.bell, color: AppColors.warning, size: 18),
                  ),
                  title: const Text('Daily Expense Reminder', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Remind at ${_notifHour.toString().padLeft(2,'0')}:${_notifMinute.toString().padLeft(2,'0')} to log transactions', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: _notifEnabled,
                  activeColor: AppColors.primary,
                  onChanged: _toggleNotifications,
                ),
                if (_notifEnabled) ...[
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.clock, color: AppColors.textMuted, size: 18),
                    title: const Text('Reminder Time', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                    trailing: TextButton(
                      onPressed: _pickTime,
                      child: Text('${_notifHour.toString().padLeft(2,'0')}:${_notifMinute.toString().padLeft(2,'0')}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Security & Sovereignty ─────────────────────────────────────
          const SectionLabel(label: 'Security & Automation'),
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.primary),
                    child: const Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 18),
                  ),
                  title: const Text('Biometric Gate', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(financeState.isBiometricEnabled ? 'Biometrics Active (Face ID / Fingerprint)' : 'Disabled — Tap to require biometric auth', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: financeState.isBiometricEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (val) async {
                    if (val) {
                      final ok = await BiometricService.authenticate(reason: 'Verify to enable Biometric Gate');
                      if (ok) {
                        financeNotifier.toggleBiometric(true);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication failed — Biometric Gate not enabled'), backgroundColor: AppColors.expense));
                      }
                    } else {
                      financeNotifier.toggleBiometric(false);
                    }
                  },
                ),
                const Divider(color: AppColors.border, height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.income),
                    child: const Icon(LucideIcons.coins, color: AppColors.income, size: 18),
                  ),
                  title: const Text('Spare-Change Round-Ups', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Automatically round-up expenses to Savings Goal', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: financeState.isRoundUpEnabled,
                  activeColor: AppColors.income,
                  onChanged: (val) => financeNotifier.toggleRoundUp(val),
                ),
                const Divider(color: AppColors.border, height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.warning),
                    child: const Icon(LucideIcons.cloud, color: AppColors.warning, size: 18),
                  ),
                  title: const Text('Auto Encrypted Backup', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Daily AES-256 local snapshot', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: financeState.isAutoBackupEnabled,
                  activeColor: AppColors.warning,
                  onChanged: (val) => financeNotifier.toggleAutoBackup(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Budget & Safety ──────────────────────────────────────────
          const SectionLabel(label: 'Budget & Safety'),
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: AppDecorations.iconBadge(AppColors.income),
                child: const Icon(LucideIcons.shieldCheck, color: AppColors.income, size: 18),
              ),
              title: const Text('Emergency Buffer', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                '${CurrencyFormatter.format(financeState.emergencyBuffer)} held back from Safe to Spend',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
              onTap: () => _showEmergencyBufferDialog(context, financeNotifier, financeState.emergencyBuffer),
            ),
          ),
          const SizedBox(height: 18),

          // ── Legal & About ────────────────────────────────────────────
          const SectionLabel(label: 'Legal & Info'),
          AppCard(
            child: Column(
              children: [
                _legalTile('Privacy Policy', LucideIcons.shield, () => context.go('/privacy-policy')),
                const Divider(color: AppColors.border, height: 1),
                _legalTile('Terms & Conditions', LucideIcons.fileText, () => context.go('/terms')),
                const Divider(color: AppColors.border, height: 1),
                _legalTile('Financial Analytics', LucideIcons.lineChart, () => context.go('/analytics')),
              ],
            ),
          ),

          // ── Admin Panel (role-gated) ──────────────────────────────────
          Consumer(builder: (context, ref, _) {
            final authState = ref.watch(authNotifierProvider);
            final userMeta = authState.user?.userMetadata;
            final isAdmin = userMeta?['app_role'] == 'admin';
            if (!isAdmin) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                const SectionLabel(label: 'Administration'),
                AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: AppDecorations.iconBadge(AppColors.expense),
                      child: const Icon(LucideIcons.shieldAlert, color: AppColors.expense, size: 18),
                    ),
                    title: const Text('Super Admin Panel', style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Platform telemetry & user overview', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
                    onTap: () => context.go('/admin'),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 24),

          // ── Sign Out ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.expense.withValues(alpha: 0.15),
                foregroundColor: AppColors.expense,
                elevation: 0,
                side: BorderSide(color: AppColors.expense.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(LucideIcons.logOut, size: 18, color: AppColors.expense),
              label: const Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.expense)),
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) context.go('/login');
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _legalTile(String title, IconData icon, VoidCallback onTap) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: AppColors.textSecondary, size: 18),
    title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
    trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
    onTap: onTap,
  );

  void _showEmergencyBufferDialog(BuildContext context, FinanceNotifier notifier, double current) {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Emergency Buffer', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Amount (${CurrencyFormatter.symbol})',
              errorText: error,
              prefixIcon: const Icon(LucideIcons.shieldCheck, color: AppColors.income, size: 18),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(ctrl.text.trim());
                if (amount == null || amount < 0) {
                  setDialogState(() => error = 'Enter a valid, non-negative amount');
                  return;
                }
                notifier.setEmergencyBuffer(amount);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String code;
  final String label;
  final Locale locale;
  final Locale current;
  final void Function(Locale) onSelect;

  const _LangChip(this.code, this.label, this.locale, this.current, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final selected = current.languageCode == locale.languageCode;
    return ChoiceChip(
      label: Text('$code  $label'),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: AppColors.surfaceLight,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
      onSelected: (_) => onSelect(locale),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String symbol;
  final String code;
  final String current;
  final void Function(String) onSelect;

  const _CurrencyChip(this.symbol, this.code, this.current, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final selected = current == symbol;
    return ChoiceChip(
      label: Text('$symbol  $code'),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: AppColors.surfaceLight,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      onSelected: (_) => onSelect(symbol),
    );
  }
}
