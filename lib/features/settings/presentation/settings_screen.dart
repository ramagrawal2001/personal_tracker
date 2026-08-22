import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricLock = true;
  bool _localNotifications = true;
  bool _cloudSync = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'SETTINGS & PRIVACY',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Security & Privacy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(LucideIcons.fingerprint, color: AppColors.primary),
                    title: const Text('App Lock & Biometrics', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Require Face ID / Fingerprint on open', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    value: _biometricLock,
                    activeColor: AppColors.primary,
                    onChanged: (val) => setState(() => _biometricLock = val),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  SwitchListTile(
                    secondary: const Icon(LucideIcons.bell, color: AppColors.accent),
                    title: const Text('Payment Reminders', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Notify 7 days, 3 days & 1 day before due date', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    value: _localNotifications,
                    activeColor: AppColors.accent,
                    onChanged: (val) => setState(() => _localNotifications = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Data & Cloud Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(LucideIcons.database, color: AppColors.income),
                    title: const Text('Local Encrypted Storage', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Drift / SQLite engine (Source of Truth)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: const Icon(LucideIcons.checkCircle2, color: AppColors.income, size: 20),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  SwitchListTile(
                    secondary: const Icon(LucideIcons.cloud, color: AppColors.transfer),
                    title: const Text('Supabase Cloud Sync', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Optional encrypted cloud backup via Edge Functions', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    value: _cloudSync,
                    activeColor: AppColors.transfer,
                    onChanged: (val) => setState(() => _cloudSync = val),
                  ),
                  if (_cloudSync) ...[
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(LucideIcons.zap, color: AppColors.warning),
                      title: const Text('Trigger Supabase Edge Sync', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Invoke "sync-ledger" & "financial-summary" edge functions', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invoking Supabase Edge Function... Sync completed!'),
                            backgroundColor: AppColors.income,
                          ),
                        );
                      },
                    ),
                  ],

                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('App Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Personal Tracker OS', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('v1.0.0', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text('Local-First Financial Operating System', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
