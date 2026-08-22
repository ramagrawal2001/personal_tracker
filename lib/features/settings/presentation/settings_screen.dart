import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/presentation/auth_repository.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification permission denied'), backgroundColor: AppColors.expense));
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
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('SETTINGS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Account ───────────────────────────────────────────────────
            _sectionLabel('Account'),
            Consumer(builder: (context, ref, _) {
              final user = ref.watch(authNotifierProvider).user;
              return _card(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.user, color: AppColors.primary, size: 20),
                  ),
                  title: Text(user?.email ?? 'Not signed in', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Supabase Auth', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.externalLink, color: AppColors.textMuted, size: 18),
                    onPressed: () => context.go('/profile'),
                  ),
                ),
              ]);
            }),

            // ── Appearance ───────────────────────────────────────────────
            _sectionLabel('Appearance'),
            _card(children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Theme', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Row(
                children: [
                  _ThemeChip('System', ThemeMode.system, themeMode, (m) => ref.read(themeProvider.notifier).setTheme(m)),
                  const SizedBox(width: 8),
                  _ThemeChip('Light', ThemeMode.light, themeMode, (m) => ref.read(themeProvider.notifier).setTheme(m)),
                  const SizedBox(width: 8),
                  _ThemeChip('Dark', ThemeMode.dark, themeMode, (m) => ref.read(themeProvider.notifier).setTheme(m)),
                ],
              ),
            ]),

            // ── Language ─────────────────────────────────────────────────
            _sectionLabel('Language'),
            _card(children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('App Language', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _LangChip('EN', 'English', const Locale('en'), locale, (l) => ref.read(localeProvider.notifier).setLocale(l)),
                  _LangChip('हिं', 'Hindi', const Locale('hi'), locale, (l) => ref.read(localeProvider.notifier).setLocale(l)),
                  _LangChip('म', 'Marathi', const Locale('mr'), locale, (l) => ref.read(localeProvider.notifier).setLocale(l)),
                ],
              ),
            ]),

            // ── Notifications ─────────────────────────────────────────────
            _sectionLabel('Notifications'),
            _card(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(LucideIcons.bell, color: AppColors.warning, size: 22),
                title: const Text('Daily Reminder', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text('Remind me at ${_notifHour.toString().padLeft(2,'0')}:${_notifMinute.toString().padLeft(2,'0')} to log transactions', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                value: _notifEnabled,
                activeColor: AppColors.warning,
                onChanged: _toggleNotifications,
              ),
              if (_notifEnabled) ...[
                const Divider(color: AppColors.border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.clock, color: AppColors.textMuted, size: 20),
                  title: const Text('Reminder Time', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  trailing: TextButton(
                    onPressed: _pickTime,
                    child: Text('${_notifHour.toString().padLeft(2,'0')}:${_notifMinute.toString().padLeft(2,'0')}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ]),

            // ── Security ─────────────────────────────────────────────────
            _sectionLabel('Security'),
            _card(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 22),
                title: const Text('Biometric Lock', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text(financeState.isBiometricEnabled ? 'Enabled — Face ID / Fingerprint' : 'OFF — Tap to enable', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                value: financeState.isBiometricEnabled,
                activeColor: AppColors.primary,
                onChanged: (val) => financeNotifier.toggleBiometric(val),
              ),
              const Divider(color: AppColors.border),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(LucideIcons.coins, color: AppColors.income, size: 22),
                title: const Text('Spare-Change Round-Ups', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: const Text('Auto round-up expenses to Savings Goal', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                value: financeState.isRoundUpEnabled,
                activeColor: AppColors.income,
                onChanged: (val) => financeNotifier.toggleRoundUp(val),
              ),
              const Divider(color: AppColors.border),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(LucideIcons.cloud, color: AppColors.warning, size: 22),
                title: const Text('Auto Vault Backup', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: const Text('Daily encrypted local snapshot', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                value: financeState.isAutoBackupEnabled,
                activeColor: AppColors.warning,
                onChanged: (val) => financeNotifier.toggleAutoBackup(val),
              ),
            ]),

            // ── Legal ────────────────────────────────────────────────────
            _sectionLabel('Legal'),
            _card(children: [
              _legalTile('Privacy Policy', LucideIcons.shield, () => context.go('/privacy-policy')),
              const Divider(color: AppColors.border, height: 1),
              _legalTile('Terms & Conditions', LucideIcons.fileText, () => context.go('/terms')),
            ]),

            // ── Analytics Shortcut ────────────────────────────────────────
            const SizedBox(height: 12),
            _card(children: [
              _legalTile('Finance Analytics', LucideIcons.pieChart, () => context.go('/analytics')),
            ]),

            // ── Admin Panel (role-gated) ──────────────────────────────────
            Consumer(builder: (context, ref, _) {
              final authState = ref.watch(authNotifierProvider);
              final userMeta = authState.user?.userMetadata;
              final isAdmin = userMeta?['app_role'] == 'admin';
              if (!isAdmin) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 12),
                _sectionLabel('Administration'),
                _card(children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.shieldAlert, color: AppColors.expense, size: 20),
                    title: const Text('Super Admin Panel', style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Platform analytics & user overview', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
                    onTap: () => context.go('/admin'),
                  ),
                ]),
              ]);
            }),

            // ── Sign Out ─────────────────────────────────────────────────
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.expense,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(LucideIcons.logOut, size: 20, color: Colors.white),
                label: const Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: () async {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8)),
  );

  Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _legalTile(String title, IconData icon, VoidCallback onTap) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: AppColors.textSecondary, size: 20),
    title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
    trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted, size: 18),
    onTap: onTap,
  );
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
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: AppColors.surfaceLight,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
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
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: AppColors.surfaceLight,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
      onSelected: (_) => onSelect(locale),
    );
  }
}
