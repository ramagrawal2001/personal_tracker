import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/smart_entry/capture_inbox.dart';
import '../../../core/services/smart_entry/native_capture_bridge.dart';
import '../../../core/services/smart_entry/parsed_transaction.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import 'quick_add_modal.dart';

/// Review inbox for auto-captured transactions. Swipe right (or ✓) to log
/// with the suggested details, tap to edit first, swipe left to dismiss.
class CaptureInboxScreen extends ConsumerStatefulWidget {
  const CaptureInboxScreen({super.key});

  @override
  ConsumerState<CaptureInboxScreen> createState() => _CaptureInboxScreenState();
}

class _CaptureInboxScreenState extends ConsumerState<CaptureInboxScreen> {
  bool _scanning = false;
  bool _captureSupported = true;

  @override
  void initState() {
    super.initState();
    NativeCaptureBridge.captureSupported().then((v) {
      if (mounted && NativeCaptureBridge.isAndroid && v != _captureSupported) setState(() => _captureSupported = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(captureInboxProvider.notifier).syncFromNative());
  }

  Future<void> _scanSms() async {
    final inbox = ref.read(captureInboxProvider.notifier);
    if (!await NativeCaptureBridge.hasSmsPermission()) {
      if (!await NativeCaptureBridge.requestSmsPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS permission is needed to read bank messages'), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }
    }
    setState(() => _scanning = true);
    final added = await inbox.scanSmsInbox(days: 7);
    if (!mounted) return;
    setState(() => _scanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added == 0 ? 'No new bank transactions in the last 7 days' : 'Found $added transaction${added == 1 ? '' : 's'} to review'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirm(CaptureItem item) async {
    final err = await ref.read(captureInboxProvider.notifier).confirm(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Logged ${CurrencyFormatter.format(item.draft.amount ?? 0)}${item.draft.merchant != null ? ' · ${item.draft.merchant}' : ''}'),
        backgroundColor: err == null ? AppColors.income : AppColors.expense,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _edit(CaptureItem item) {
    QuickAddModal.show(context, initialDraft: item.draft, captureId: item.id);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(captureInboxProvider);
    final fin = ref.watch(financeNotifierProvider);
    final items = inbox.items;
    final captureOff = NativeCaptureBridge.isAndroid && _captureSupported && !inbox.smsEnabled && !inbox.notificationsEnabled;

    return AppScaffold(
      title: 'Review Inbox',
      showBackButton: true,
      actions: [
        if (NativeCaptureBridge.isAndroid && _captureSupported)
          IconButton(
            tooltip: 'Scan SMS from the last 7 days',
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(LucideIcons.messageSquare, color: AppColors.textSecondary),
            onPressed: _scanning ? null : _scanSms,
          ),
        if (items.isNotEmpty)
          PopupMenuButton<String>(
            icon: Icon(LucideIcons.moreVertical, color: AppColors.textSecondary),
            color: AppColors.surface,
            onSelected: (v) async {
              if (v == 'clear') await ref.read(captureInboxProvider.notifier).clearAll();
            },
            itemBuilder: (_) => [PopupMenuItem(value: 'clear', child: Text('Dismiss all', style: TextStyle(color: AppColors.textPrimary)))],
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (captureOff)
            _InfoBanner(
              icon: LucideIcons.zap,
              text: 'Turn on auto-capture to have bank SMS and UPI payments land here automatically.',
              action: 'Set up',
              onTap: () => context.push('/settings/smart-logging'),
            ),
          if (NativeCaptureBridge.isAndroid && !_captureSupported && items.isEmpty)
            _InfoBanner(
              icon: LucideIcons.zap,
              text: 'Forward bank SMS here automatically with a free automation app (MacroDroid).',
              action: 'How',
              onTap: () => context.push('/settings/smart-logging'),
            ),
          if (NativeCaptureBridge.isIOS)
            _InfoBanner(
              icon: LucideIcons.smartphone,
              text: 'On iPhone, add a Shortcuts automation to send bank SMS here automatically.',
              action: 'How',
              onTap: () => context.push('/settings/smart-logging'),
            ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: LucideIcons.inbox,
                title: 'All caught up',
                description: 'Transactions detected from bank SMS, payment-app notifications, shared text and Shortcuts show up here for a one-tap confirm.',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Text(
                '${items.length} to review · swipe right to log, left to dismiss',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            for (final item in items)
              Dismissible(
                key: ValueKey(item.id),
                background: _swipeBg(AppColors.income, LucideIcons.check, 'Log', Alignment.centerLeft),
                secondaryBackground: _swipeBg(AppColors.expense, LucideIcons.x, 'Dismiss', Alignment.centerRight),
                confirmDismiss: (dir) async {
                  if (dir == DismissDirection.startToEnd) {
                    await _confirm(item);
                    return false; // the list rebuilds from provider state
                  }
                  await ref.read(captureInboxProvider.notifier).dismiss(item.id);
                  return false;
                },
                child: _CaptureCard(item: item, fin: fin, onConfirm: () => _confirm(item), onEdit: () => _edit(item)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _swipeBg(Color c, IconData icon, String label, Alignment align) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: align,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 18),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
        ]),
      );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;
  const _InfoBanner({required this.icon, required this.text, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        TextButton(onPressed: onTap, child: Text(action)),
      ]),
    );
  }
}

class _CaptureCard extends StatelessWidget {
  final CaptureItem item;
  final FinanceState fin;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;

  const _CaptureCard({required this.item, required this.fin, required this.onConfirm, required this.onEdit});

  IconData get _sourceIcon => switch (item.source) {
        CaptureSource.sms => LucideIcons.messageSquare,
        CaptureSource.notification => LucideIcons.bell,
        CaptureSource.shortcut => LucideIcons.smartphone,
        CaptureSource.share => LucideIcons.share2,
        CaptureSource.receipt => LucideIcons.receipt,
        CaptureSource.voice => LucideIcons.mic,
        CaptureSource.typed => LucideIcons.keyboard,
      };

  @override
  Widget build(BuildContext context) {
    final d = item.draft;
    final isIncome = d.type == TransactionType.income;
    final color = isIncome ? AppColors.income : AppColors.expense;

    String? instrument;
    if (d.payCardId == kCashPaySentinel) {
      instrument = 'Cash';
    } else if (d.payCardId != null) {
      for (final c in fin.creditCards) {
        if (c.id == d.payCardId) instrument = '${c.name} ••${c.last4}';
      }
    }
    if (instrument == null && d.accountId != null) {
      for (final a in fin.accounts) {
        if (a.id == d.accountId) instrument = a.name;
      }
    }
    instrument ??= d.last4 != null ? 'A/c ••${d.last4} (not matched)' : null;

    String? category;
    for (final c in fin.categories) {
      if (c.id == d.categoryId) category = c.name;
    }

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: AppDecorations.card(radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: AppDecorations.iconBadge(color),
              child: Icon(isIncome ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  d.merchant ?? (isIncome ? 'Money received' : 'Payment'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    DateFormatter.formatShort(d.date ?? item.receivedAt),
                    if (category != null) category,
                    if (instrument != null) instrument,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ]),
            ),
            Text(
              '${isIncome ? '+' : '−'}${CurrencyFormatter.format(d.amount ?? 0)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ]),
          if (d.rawText != null) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_sourceIcon, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.rawText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.3),
                ),
              ),
            ]),
          ],
          if (item.possibleDuplicateOf != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(LucideIcons.alertTriangle, size: 13, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Looks like one you already logged — dismiss if it is.',
                    style: TextStyle(fontSize: 11, color: AppColors.warning)),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: Icon(LucideIcons.pencil, size: 14, color: AppColors.textSecondary),
              label: Text('Edit', style: TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              key: ValueKey('confirm_${item.id}'),
              onPressed: onConfirm,
              icon: const Icon(LucideIcons.check, size: 15),
              label: const Text('Log it'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
