import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../domain/models/models.dart';
import 'quick_add_modal.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  TransactionType? _filterType;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final query = _searchController.text.trim().toLowerCase();

    final filtered = financeState.transactions.where((tx) {
      if (_filterType != null && tx.type != _filterType) return false;
      if (query.isNotEmpty) {
        final merchant = tx.merchant?.toLowerCase() ?? '';
        final desc = tx.description?.toLowerCase() ?? '';
        final notes = tx.notes?.toLowerCase() ?? '';
        final amountStr = tx.amount.toString();
        return merchant.contains(query) || desc.contains(query) || notes.contains(query) || amountStr.contains(query);
      }
      return true;
    }).toList();

    return AppScaffold(
      title: 'Transactions',
      actions: [
        AppScaffold.addAction(onPressed: () => QuickAddModal.show(context)),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip(null, 'All'),
                _buildFilterChip(TransactionType.expense, 'Expenses'),
                _buildFilterChip(TransactionType.income, 'Income'),
                _buildFilterChip(TransactionType.transfer, 'Transfers'),
                _buildFilterChip(TransactionType.creditCardPayment, 'Card Pay'),
                _buildFilterChip(TransactionType.loanPayment, 'Loan Pay'),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: EmptyState(
                        icon: LucideIcons.receipt,
                        title: query.isNotEmpty ? 'No matches found' : 'No transactions yet',
                        description: query.isNotEmpty
                            ? 'Try a different search term or filter.'
                            : 'Tap + to record your first transaction.',
                        actionLabel: query.isEmpty ? 'Add Transaction' : null,
                        onAction: query.isEmpty ? () => QuickAddModal.show(context) : null,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildTransactionTile(filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income || tx.type == TransactionType.refund;
    final isTransfer = tx.type == TransactionType.transfer ||
        tx.type == TransactionType.creditCardPayment ||
        tx.type == TransactionType.loanPayment;

    final color = isIncome ? AppColors.income : isTransfer ? AppColors.transfer : AppColors.expense;
    final icon = isIncome ? LucideIcons.arrowDownLeft : isTransfer ? LucideIcons.arrowRightLeft : LucideIcons.arrowUpRight;

    return Dismissible(
      key: Key(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.expense, borderRadius: BorderRadius.circular(14)),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text('Delete transaction?', style: TextStyle(color: AppColors.textPrimary)),
                content: Text('This cannot be undone.', style: TextStyle(color: AppColors.textMuted)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.expense))),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) {
        ref.read(financeNotifierProvider.notifier).deleteTransaction(tx.id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction deleted')));
      },
      child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => QuickAddModal.show(context, existing: tx),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppDecorations.card(radius: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: AppDecorations.iconBadge(color),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.merchant ?? tx.description ?? tx.type.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormatter.formatShort(tx.date)}${tx.description != null ? " • ${tx.description}" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${isIncome ? '+' : '-'}${CurrencyFormatter.format(tx.amount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildFilterChip(TransactionType? type, String label) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        onSelected: (_) {
          setState(() => _filterType = isSelected ? null : type);
        },
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        ),
        tooltip: 'Filter by: $label',
      ),
    );
  }
}
