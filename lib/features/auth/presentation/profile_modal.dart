import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/biometric_service.dart';
import 'auth_repository.dart';
import '../../../core/utils/responsive.dart';


class ProfileModal extends ConsumerWidget {
  const ProfileModal({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const ProfileModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'User Profile & Account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // User Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.user, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user != null ? user.email ?? 'Authenticated Account' : 'Finance OS Account',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.income.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Encrypted Sync Active',
                          style: TextStyle(
                            color: AppColors.income,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),


          // Feature Toggles & Preferences Section
          const Text('Security & Vault Preferences', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
          const SizedBox(height: 10),

          Consumer(
            builder: (context, ref, _) {
              final financeState = ref.watch(financeNotifierProvider);
              final notifier = ref.read(financeNotifierProvider.notifier);

              return Column(
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 20),
                    title: const Text('Biometric Security Lock', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Require Face ID / Fingerprint on launch', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    value: financeState.isBiometricEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) async {
                      if (val) {
                        final ok = await BiometricService.authenticate(reason: 'Verify to enable Biometric Security Lock');
                        if (ok) {
                          notifier.toggleBiometric(true);
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication failed'), backgroundColor: AppColors.expense));
                        }
                      } else {
                        notifier.toggleBiometric(false);
                      }
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(LucideIcons.coins, color: AppColors.income, size: 20),
                    title: const Text('Spare-Change Round-Ups', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Auto round-up expenses & transfer to Savings Goal', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    value: financeState.isRoundUpEnabled,
                    activeColor: AppColors.income,
                    onChanged: (val) => notifier.toggleRoundUp(val),
                  ),
                  const SizedBox(height: 12),

                  // 100% Encrypted Local Backup & Restore Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                          icon: const Icon(LucideIcons.download, size: 16),
                          label: const Text('Export Vault', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            try {
                              final snapshot = await ref.read(appDatabaseProvider).exportSnapshot();
                              await BackupService.saveBackupToDisk(snapshot);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Encrypted Vault Exported!'), backgroundColor: AppColors.income),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.expense),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                          icon: const Icon(LucideIcons.upload, size: 16),
                          label: const Text('Restore Vault', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: const Text('Restore Vault?', style: TextStyle(color: AppColors.textPrimary)),
                                content: const Text(
                                  'This replaces all current data with the last exported snapshot. This cannot be undone.',
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore', style: TextStyle(color: AppColors.expense))),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              final snapshot = await BackupService.loadBackupFromDisk();
                              if (snapshot == null) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No valid backup found on this device'), backgroundColor: AppColors.expense),
                                );
                                return;
                              }
                              await ref.read(appDatabaseProvider).importSnapshot(snapshot);
                              await ref.read(financeNotifierProvider.notifier).reloadFromDb();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Local Encrypted Vault restored successfully!'), backgroundColor: AppColors.income),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Restore failed: $e'), backgroundColor: AppColors.expense),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Action Buttons

          if (user != null || authState.isAuthenticated)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.expense,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(LucideIcons.logOut, size: 18, color: Colors.white),
                label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(LucideIcons.logIn, size: 18, color: Colors.white),
                label: const Text('Sign In to Account', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/login');
                },
              ),
            ),

        ],
      ),
    );
  }
}
