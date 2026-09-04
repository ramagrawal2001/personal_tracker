import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/models/user_profile_model.dart';
import 'auth_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  DateTime? _dob;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;
    await ref.read(userProfileProvider.notifier).loadProfile(user.id);
    final profile = ref.read(userProfileProvider);
    if (profile != null) {
      _nameCtrl.text = profile.displayName;
      _mobileCtrl.text = profile.mobile ?? '';
      setState(() => _dob = profile.dateOfBirth);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 400);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final base64Str = base64Encode(bytes);
    final profile = ref.read(userProfileProvider);
    if (profile != null) {
      await ref.read(userProfileProvider.notifier).saveProfile(profile.copyWith(avatarBase64: base64Str));
      setState(() {});
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;
    final existing = ref.read(userProfileProvider) ?? UserProfileModel(userId: user.id);
    await ref.read(userProfileProvider.notifier).saveProfile(existing.copyWith(
      displayName: _nameCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim().isEmpty ? null : _mobileCtrl.text.trim(),
      dateOfBirth: _dob,
    ));
    setState(() { _saving = false; _editing = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile saved ✓'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.dark(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _exportVault() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final snapshot = await db.exportSnapshot();
      await BackupService.saveBackupToDisk(snapshot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault exported ✓ (encrypted, on-device)'), backgroundColor: AppColors.income),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.expense),
      );
    }
  }

  Future<void> _restoreVault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Restore Vault?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'This replaces all current accounts, transactions, cards, loans, budgets, investments and goals with the last exported snapshot. This cannot be undone.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Restore', style: TextStyle(color: AppColors.expense))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final snapshot = await BackupService.loadBackupFromDisk();
      if (snapshot == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No valid backup found on this device'), backgroundColor: AppColors.expense),
        );
        return;
      }
      final db = ref.read(appDatabaseProvider);
      await db.importSnapshot(snapshot);
      await ref.read(financeNotifierProvider.notifier).reloadFromDb();
      await ref.read(notesProvider.notifier).reloadFromDb();
      // The restore wrote rows straight to Drift, bypassing every mutator —
      // push everything straight to the cloud so it converges too.
      await ref.read(financeNotifierProvider.notifier).pushAllToCloud();
      await ref.read(notesProvider.notifier).pushAllToCloud();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault restored ✓'), backgroundColor: AppColors.income),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e'), backgroundColor: AppColors.expense),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;
    final financeState = ref.watch(financeNotifierProvider);
    final notifier = ref.read(financeNotifierProvider.notifier);
    final profile = ref.watch(userProfileProvider);

    final avatarBytes = profile?.avatarBase64 != null ? base64Decode(profile!.avatarBase64!) : null;
    final initials = profile?.initials ?? (user?.email?.substring(0, 1).toUpperCase() ?? '?');

    return AppScaffold(
      title: 'Profile & Security',
      showBackButton: true,
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => setState(() => _editing = !_editing),
          child: Text(_editing ? 'Cancel' : 'Edit', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + basic info ───────────────────────────────────────
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _editing ? _pickImage : null,
                  child: Stack(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.2),
                          border: Border.all(color: AppColors.primary, width: 2),
                          image: avatarBytes != null
                              ? DecorationImage(image: MemoryImage(avatarBytes), fit: BoxFit.cover)
                              : null,
                        ),
                        child: avatarBytes == null
                            ? Center(child: Text(initials, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary)))
                            : null,
                      ),
                      if (_editing)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: const Icon(LucideIcons.camera, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  profile?.displayName.isNotEmpty == true ? profile!.displayName : (user?.email ?? 'Aspyric User'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(user?.email ?? '', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.income.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text('Verified Account', style: TextStyle(color: AppColors.income, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Personal Info ─────────────────────────────────────────────
          const SectionLabel(label: 'Personal Information'),
          AppCard(
            child: Column(
              children: [
                _field('Full Name', LucideIcons.user, _nameCtrl, enabled: _editing, hint: 'Enter your full name'),
                Divider(color: AppColors.border, height: 1),
                _field('Mobile Number', LucideIcons.phone, _mobileCtrl, enabled: _editing, hint: '+91 00000 00000', keyboardType: TextInputType.phone),
                Divider(color: AppColors.border, height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(LucideIcons.calendar, color: AppColors.textMuted, size: 20),
                  title: Text('Date of Birth', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  subtitle: Text(
                    _dob != null ? '${_dob!.day}/${_dob!.month}/${_dob!.year}' : 'Not set',
                    style: TextStyle(color: _dob != null ? AppColors.textPrimary : AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  trailing: _editing ? IconButton(icon: Icon(LucideIcons.pencil, size: 16, color: AppColors.primary), onPressed: _pickDob) : null,
                ),
                Divider(color: AppColors.border, height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(LucideIcons.mail, color: AppColors.textMuted, size: 20),
                  title: Text('Email Address', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  subtitle: Text(user?.email ?? '', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ],
            ),
          ),

          if (_editing) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ── Security ─────────────────────────────────────────────────
          const SectionLabel(label: 'Security & Biometrics'),
          AppCard(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 22),
              title: Text('Biometric Lock', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(financeState.isBiometricEnabled ? 'Face ID / Fingerprint enabled' : 'OFF — tap to enable', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              value: financeState.isBiometricEnabled,
              activeColor: AppColors.primary,
              onChanged: (val) async {
                if (val) {
                  final ok = await BiometricService.authenticate(reason: 'Verify to enable Biometric Lock');
                  if (ok) {
                    notifier.toggleBiometric(true);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Biometric Lock enabled ✓'), backgroundColor: AppColors.income));
                  } else {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authentication failed'), backgroundColor: AppColors.expense));
                  }
                } else {
                  notifier.toggleBiometric(false);
                }
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── Data Vault ────────────────────────────────────────────────
          const SectionLabel(label: 'Data Sovereignty Vault'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text('100% AES-256 encrypted local vault snapshot.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: AppColors.primary)),
                          icon: Icon(LucideIcons.download, size: 18, color: AppColors.primary),
                          label: Text('Export', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          onPressed: _exportVault,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: AppColors.income)),
                          icon: Icon(LucideIcons.upload, size: 18, color: AppColors.income),
                          label: Text('Restore', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.income)),
                          onPressed: _restoreVault,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Sign Out ──────────────────────────────────────────────────
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
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _field(String label, IconData icon, TextEditingController ctrl, {bool enabled = true, String? hint, TextInputType? keyboardType}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: AppColors.textMuted, size: 20),
      title: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      subtitle: enabled
          ? TextField(
              controller: ctrl,
              keyboardType: keyboardType,
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                filled: false,
              ),
            )
          : Text(ctrl.text.isEmpty ? (hint ?? 'Not set') : ctrl.text, style: TextStyle(color: ctrl.text.isEmpty ? AppColors.textMuted : AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }
}
