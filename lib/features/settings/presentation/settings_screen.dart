import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/payment_reminders.dart';
import '../../../core/services/secret_cipher_service.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/sync/sync_status.dart';
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
  bool _payRemindersEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotifState();
    _maybeShowRecoveryCodeOnce();
  }

  /// Surfaces the one-time recovery code right after a fresh sign-up.
  Future<void> _maybeShowRecoveryCodeOnce() async {
    final code = await ref.read(secretCipherServiceProvider).takeRecoveryCodeForOneTimeDisplay();
    if (code != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRecoveryCodeDialog(code, firstTime: true));
    }
  }

  Future<void> _showRecoveryCodeDialog(String? code, {bool firstTime = false}) async {
    code ??= await ref.read(secretCipherServiceProvider).getRecoveryCode();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          Icon(LucideIcons.shieldCheck, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text('Recovery code', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              code == null
                  ? 'This device was set up from a password or a recovery code, so it does not hold the recovery code itself. Check the device where you first signed up.'
                  : firstTime
                      ? 'Write this down and keep it safe. It is the only way to recover your encrypted card & bank details if you lose every signed-in device and forget your password.'
                      : 'Keep this somewhere safe. It unlocks your encrypted card & bank details on a new device if you forget your password.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            if (code != null) ...[
              const SizedBox(height: 14),
              SelectableText(
                code,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
        actions: [
          if (code != null)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code!));
                Navigator.pop(ctx);
              },
              child: Text('Copy', style: TextStyle(color: AppColors.primary)),
            ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _loadNotifState() async {
    final enabled = await NotificationService.isEnabled();
    final hour = await NotificationService.getReminderHour();
    final min = await NotificationService.getReminderMinute();
    final payRem = await NotificationService.paymentRemindersEnabled();
    if (mounted) setState(() { _notifEnabled = enabled; _notifHour = hour; _notifMinute = min; _payRemindersEnabled = payRem; });
  }

  Future<void> _toggleNotifications(bool val) async {
    if (val) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification permission denied'), backgroundColor: AppColors.expense, behavior: SnackBarBehavior.floating),
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
    final themeMode = ref.watch(themeProvider);

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
                  child: Icon(LucideIcons.user, color: AppColors.primary, size: 20),
                ),
                title: Text(user?.email ?? 'Not signed in', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text('Local Encrypted & Cloud Synced', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                trailing: Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
                onTap: () => context.push('/profile'),
              ),
            );
          }),
          const SizedBox(height: 18),

          // ── Cloud Sync ───────────────────────────────────────────────
          const SectionLabel(label: 'Cloud Sync'),
          Consumer(builder: (context, ref, _) {
            final sync = ref.watch(syncStatusProvider);
            final online = sync.isOnline;
            final parts = <String>[
              online ? 'Online' : 'Offline',
              '${sync.pendingCount} pending',
            ];
            if (sync.lastSyncTime != null) {
              final t = sync.lastSyncTime!;
              parts.add('last ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
            }
            return AppCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: AppDecorations.iconBadge(online ? AppColors.income : AppColors.textMuted),
                      child: Icon(LucideIcons.refreshCw,
                          color: online ? AppColors.income : AppColors.textMuted, size: 18),
                    ),
                    title: Text('Sync Status',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(parts.join(' • '),
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: sync.isSyncing
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () => ref.read(syncServiceProvider).flushNow(),
                            child: Text('Sync now',
                                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                  ),
                  if (sync.deadLetterCount > 0) ...[
                    Divider(color: AppColors.border, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(LucideIcons.alertTriangle, color: AppColors.expense, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${sync.deadLetterCount} item(s) failed to sync and were parked',
                                style: TextStyle(color: AppColors.expense, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 18),

          // ── Appearance ───────────────────────────────────────────────
          const SectionLabel(label: 'Appearance & Theme'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme Mode', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ThemeChip('System', ThemeMode.system, themeMode, (m) => ref.read(themeProvider.notifier).setTheme(m)),
                    const SizedBox(width: 8),
                    _ThemeChip('Light', ThemeMode.light, themeMode, (m) => ref.read(themeProvider.notifier).setTheme(m)),
                    const SizedBox(width: 8),
                    _ThemeChip('Dark', ThemeMode.dark, themeMode, (m) => ref.read(themeProvider.notifier).setTheme(m)),
                  ],
                ),
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
                Text('Application Language', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
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
                Text('Currency Symbol', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
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
                      Icon(LucideIcons.eye, color: AppColors.textMuted, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Preview: ${CurrencyFormatter.format(100000)} • ${CurrencyFormatter.format(25499.50, showDecimals: true)}',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'monospace'),
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
                    child: Icon(LucideIcons.bell, color: AppColors.warning, size: 18),
                  ),
                  title: Text('Daily Expense Reminder', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Remind at ${_notifHour.toString().padLeft(2,'0')}:${_notifMinute.toString().padLeft(2,'0')} to log transactions', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: _notifEnabled,
                  activeColor: AppColors.primary,
                  onChanged: _toggleNotifications,
                ),
                if (_notifEnabled) ...[
                  Divider(color: AppColors.border, height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(LucideIcons.clock, color: AppColors.textMuted, size: 18),
                    title: Text('Reminder Time', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                    trailing: TextButton(
                      onPressed: _pickTime,
                      child: Text('${_notifHour.toString().padLeft(2,'0')}:${_notifMinute.toString().padLeft(2,'0')}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
                Divider(color: AppColors.border, height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.creditCard),
                    child: Icon(LucideIcons.calendarClock, color: AppColors.creditCard, size: 18),
                  ),
                  title: Text('Payment Reminders', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Card statement & due dates, EMIs, recurring bills', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: _payRemindersEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (v) async {
                    setState(() => _payRemindersEnabled = v);
                    await NotificationService.setPaymentRemindersEnabled(v);
                    if (v) {
                      await NotificationService.schedulePaymentReminders(
                        PaymentReminders.compute(ref.read(financeNotifierProvider), DateTime.now()),
                      );
                    }
                  },
                ),
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
                    child: Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 18),
                  ),
                  title: Text('Biometric Gate', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(financeState.isBiometricEnabled ? 'Biometrics Active (Face ID / Fingerprint)' : 'Disabled — Tap to require biometric auth', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: financeState.isBiometricEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (val) async {
                    if (val) {
                      final ok = await BiometricService.authenticate(reason: 'Verify to enable Biometric Gate');
                      if (ok) {
                        financeNotifier.toggleBiometric(true);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authentication failed — Biometric Gate not enabled'), backgroundColor: AppColors.expense));
                      }
                    } else {
                      financeNotifier.toggleBiometric(false);
                    }
                  },
                ),
                Divider(color: AppColors.border, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.primary),
                    child: Icon(LucideIcons.shieldCheck, color: AppColors.primary, size: 18),
                  ),
                  title: Text('Encryption Recovery Code', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Recovers your encrypted card & bank details on a new device', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  trailing: Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
                  onTap: () => _showRecoveryCodeDialog(null),
                ),
                Divider(color: AppColors.border, height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.income),
                    child: Icon(LucideIcons.coins, color: AppColors.income, size: 18),
                  ),
                  title: Text('Spare-Change Round-Ups', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Automatically round-up expenses to Savings Goal', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  value: financeState.isRoundUpEnabled,
                  activeColor: AppColors.income,
                  onChanged: (val) => financeNotifier.toggleRoundUp(val),
                ),
                Divider(color: AppColors.border, height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.warning),
                    child: Icon(LucideIcons.cloud, color: AppColors.warning, size: 18),
                  ),
                  title: Text('Auto Encrypted Backup', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Daily AES-256 local snapshot', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
                child: Icon(LucideIcons.shieldCheck, color: AppColors.income, size: 18),
              ),
              title: Text('Emergency Buffer', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                '${CurrencyFormatter.format(financeState.emergencyBuffer)} held back from Safe to Spend',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              trailing: Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
              onTap: () => _showEmergencyBufferDialog(context, financeNotifier, financeState.emergencyBuffer),
            ),
          ),
          const SizedBox(height: 18),

          // ── Legal & About ────────────────────────────────────────────
          const SectionLabel(label: 'Legal & Info'),
          AppCard(
            child: Column(
              children: [
                _legalTile('Privacy Policy', LucideIcons.shield, () => context.push('/privacy-policy')),
                Divider(color: AppColors.border, height: 1),
                _legalTile('Terms & Conditions', LucideIcons.fileText, () => context.push('/terms')),
                Divider(color: AppColors.border, height: 1),
                _legalTile('Financial Analytics', LucideIcons.lineChart, () => context.push('/analytics')),
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
                      child: Icon(LucideIcons.shieldAlert, color: AppColors.expense, size: 18),
                    ),
                    title: Text('Super Admin Panel', style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('Platform telemetry & user overview', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
                    onTap: () => context.push('/admin'),
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
              icon: Icon(LucideIcons.logOut, size: 18, color: AppColors.expense),
              label: Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.expense)),
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
    title: Text(title, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
    trailing: Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
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
          title: Text('Emergency Buffer', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Amount (${CurrencyFormatter.symbol})',
              errorText: error,
              prefixIcon: Icon(LucideIcons.shieldCheck, color: AppColors.income, size: 18),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
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

class _ThemeChip extends StatelessWidget {
  final String label;
  final ThemeMode mode;
  final ThemeMode current;
  final void Function(ThemeMode) onSelect;

  const _ThemeChip(this.label, this.mode, this.current, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final selected = current == mode;
    return ChoiceChip(
      label: Text(label),
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
      onSelected: (_) => onSelect(mode),
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
