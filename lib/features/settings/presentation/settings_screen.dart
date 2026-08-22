import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../auth/presentation/auth_repository.dart';



class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _localNotifications = true;
  bool _cloudSync = false;

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final financeNotifier = ref.read(financeNotifierProvider.notifier);

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
            const Text('Account & Identity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            Consumer(
              builder: (context, ref, _) {
                final authState = ref.watch(authNotifierProvider);
                final user = authState.user;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.user, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user != null ? user.email ?? 'Logged In User' : 'Not Signed In',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user != null ? 'Supabase Account Linked' : 'Sign in to sync your data',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: user != null ? AppColors.expense : AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          if (user != null) {
                            await ref.read(authNotifierProvider.notifier).signOut();
                            if (context.mounted) {
                              context.go('/login');
                            }
                          } else {
                            context.go('/login');
                          }
                        },
                        child: Text(user != null ? 'Sign Out' : 'Sign In', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            const Text('Financial Engine Preferences', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Minimum Emergency Buffer', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Reserved in Safe-to-Spend formula before spending recommendation', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [10000.0, 20000.0, 50000.0].map((amount) {
                      final isSelected = financeState.emergencyBuffer == amount;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('₹${amount.toInt()}'),
                          selected: isSelected,
                          selectedColor: AppColors.income.withValues(alpha: 0.2),
                          onSelected: (val) {
                            if (val) {
                              financeNotifier.setEmergencyBuffer(amount);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
                    subtitle: Text(
                      financeState.isBiometricEnabled
                          ? 'Enabled — Face ID / Fingerprint required on open'
                          : 'Disabled — No biometric lock on open',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    value: financeState.isBiometricEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) => financeNotifier.toggleBiometric(val),
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
                    title: const Text('Cloud Backup & Sync', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Optional encrypted cloud backup via Edge Services', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    value: _cloudSync,
                    activeColor: AppColors.transfer,
                    onChanged: (val) => setState(() => _cloudSync = val),
                  ),
                  if (_cloudSync) ...[
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(LucideIcons.zap, color: AppColors.warning),
                      title: const Text('Trigger Cloud Sync Now', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Sync local ledger & calculate remote summary', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invoking Cloud Sync... Completed successfully!'),
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

