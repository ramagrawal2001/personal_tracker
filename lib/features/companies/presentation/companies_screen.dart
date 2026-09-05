import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/models.dart';

/// Employer registry. A company is what salary transactions and payday
/// reminders attach to — switching jobs is "make a different company
/// current" rather than editing a single mutable "employer" field.
class CompaniesScreen extends ConsumerWidget {
  const CompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(financeNotifierProvider).companies;
    // Current employer first, then most recently joined.
    final sorted = [...companies]..sort((a, b) {
        if (a.isCurrentEmployer != b.isCurrentEmployer) {
          return a.isCurrentEmployer ? -1 : 1;
        }
        final ad = a.joinedDate;
        final bd = b.joinedDate;
        if (ad == null || bd == null) return 0;
        return bd.compareTo(ad);
      });

    return AppScaffold(
      title: 'Companies',
      actions: [
        AppScaffold.addAction(onPressed: () => _showAddEditSheet(context, ref)),
      ],
      scrollable: true,
      body: sorted.isEmpty
          ? EmptyState(
              icon: LucideIcons.building2,
              title: 'No companies yet',
              description: 'Add the companies you work or have worked for — salary credits and PF contributions attach to one of these.',
              actionLabel: 'Add Company',
              onAction: () => _showAddEditSheet(context, ref),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildCompanyCard(context, ref, sorted[index]),
            ),
    );
  }

  Widget _buildCompanyCard(BuildContext context, WidgetRef ref, CompanyModel company) {
    final accounts = ref.read(financeNotifierProvider).accountsWithCalculatedBalances;
    AccountModel? defaultAccount;
    if (company.defaultBankAccountId != null) {
      for (final a in accounts) {
        if (a.id == company.defaultBankAccountId) {
          defaultAccount = a;
          break;
        }
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.iconBadge(
                  company.isCurrentEmployer ? AppColors.income : AppColors.textMuted,
                  circle: true,
                ),
                child: Icon(LucideIcons.building2, color: company.isCurrentEmployer ? AppColors.income : AppColors.textMuted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            company.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15),
                          ),
                        ),
                        if (company.isCurrentEmployer) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.income.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Current', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.income)),
                          ),
                        ],
                      ],
                    ),
                    if (company.joinedDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Joined ${company.joinedDate!.day}/${company.joinedDate!.month}/${company.joinedDate!.year}',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                    if (defaultAccount != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Default: ${defaultAccount.name}${company.defaultPfAmount != null ? ' · PF ${CurrencyFormatter.format(company.defaultPfAmount!)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.pencil, color: AppColors.primary, size: 16),
                    onPressed: () => _showAddEditSheet(context, ref, existing: company),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.trash2, color: AppColors.textMuted, size: 18),
                    onPressed: () => _confirmDelete(context, ref, company),
                  ),
                ],
              ),
            ],
          ),
          if (!company.isCurrentEmployer) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(LucideIcons.arrowRightCircle, size: 16, color: AppColors.income),
                label: Text('Make current employer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.income)),
                onPressed: () async {
                  try {
                    await ref.read(financeNotifierProvider.notifier).setCurrentEmployer(company.id);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.expense),
                    );
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddEditSheet(BuildContext context, WidgetRef ref, {CompanyModel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final pfCtrl = TextEditingController(text: existing?.defaultPfAmount?.toStringAsFixed(0) ?? '');
    DateTime? joinedDate = existing?.joinedDate;
    String? bankAccountId = existing?.defaultBankAccountId;
    bool isCurrent = existing?.isCurrentEmployer ?? false;
    String? error;

    final accounts = ref.read(financeNotifierProvider).accountsWithCalculatedBalances.where((a) => !a.isDeleted).toList();
    if (bankAccountId != null && !accounts.any((a) => a.id == bankAccountId)) bankAccountId = null;

    AdaptiveModal.show(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(existing != null ? 'Edit Company' : 'Add Company', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(labelText: 'Company Name', errorText: error),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: joinedDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setSheetState(() => joinedDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Joined Date (optional)'),
                    child: Text(
                      joinedDate != null ? '${joinedDate!.day}/${joinedDate!.month}/${joinedDate!.year}' : 'Not set',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Salary defaults (optional — pre-fill Log Salary)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: bankAccountId,
                  dropdownColor: AppColors.surface,
                  decoration: const InputDecoration(labelText: 'Default Bank Account'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None')),
                    ...accounts.map((a) => DropdownMenuItem<String?>(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setSheetState(() => bankAccountId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pfCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(labelText: 'Default PF Contribution (${CurrencyFormatter.symbol})'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Currently employed here', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  // Turning this off here would have no effect — there's no
                  // "no current employer" state, only "some other company is
                  // now current" (setCurrentEmployer). So once a company is
                  // current, un-setting it must happen by making a different
                  // one current instead, not from this switch.
                  subtitle: (existing?.isCurrentEmployer ?? false)
                      ? Text('Make another company current to change this', style: TextStyle(color: AppColors.textMuted, fontSize: 11))
                      : null,
                  value: isCurrent,
                  activeColor: AppColors.income,
                  onChanged: (existing?.isCurrentEmployer ?? false) ? null : (v) => setSheetState(() => isCurrent = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setSheetState(() => error = 'Enter a company name');
                        return;
                      }
                      final pf = pfCtrl.text.trim().isEmpty ? null : double.tryParse(pfCtrl.text.trim());
                      try {
                        final notifier = ref.read(financeNotifierProvider.notifier);
                        if (existing != null) {
                          await notifier.updateCompany(
                            existing.id,
                            name: name,
                            joinedDate: joinedDate,
                            defaultBankAccountId: bankAccountId,
                            defaultPfAmount: pf,
                          );
                          if (isCurrent != existing.isCurrentEmployer && isCurrent) {
                            await notifier.setCurrentEmployer(existing.id);
                          }
                        } else {
                          await notifier.addCompany(
                            name: name,
                            joinedDate: joinedDate,
                            isCurrentEmployer: isCurrent,
                            defaultBankAccountId: bankAccountId,
                            defaultPfAmount: pf,
                          );
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                      } catch (e) {
                        setSheetState(() => error = 'Failed to save: $e');
                      }
                    },
                    child: Text(existing != null ? 'Save Changes' : 'Add Company'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, CompanyModel company) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete company?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "${company.name}"? Past salary transactions keep their record but lose this company link.', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(financeNotifierProvider.notifier).deleteCompany(company.id);
                if (!context.mounted) return;
                showUndoDeleteSnackBar(
                  context,
                  message: '"${company.name}" deleted',
                  onUndo: () => ref.read(financeNotifierProvider.notifier).undoDelete('companies', company.id),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.expense),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
  }
}
