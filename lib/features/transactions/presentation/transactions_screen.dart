import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
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

    List<TransactionModel> filtered = financeState.transactions.where((tx) {
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'TRANSACTIONS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, color: AppColors.primary),
            onPressed: () => QuickAddModal.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search merchant, category, notes...',
                prefixIcon: const Icon(LucideIcons.search, color: AppColors.textMuted, size: 20),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, color: AppColors.textMuted, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          const SizedBox(height: 8),

          // Transactions Ledger List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No matching transactions found', style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      final isIncome = tx.type == TransactionType.income || tx.type == TransactionType.refund;
                      final isTransfer = tx.type == TransactionType.transfer ||
                          tx.type == TransactionType.creditCardPayment ||
                          tx.type == TransactionType.loanPayment;

                      final Color color = isIncome
                          ? AppColors.income
                          : isTransfer
                              ? AppColors.transfer
                              : AppColors.expense;

                      final IconData icon = isIncome
                          ? LucideIcons.arrowDownLeft
                          : isTransfer
                              ? LucideIcons.arrowRightLeft
                              : LucideIcons.arrowUpRight;

                      return Dismissible(
                        key: Key(tx.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppColors.expense,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(LucideIcons.trash2, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          ref.read(financeNotifierProvider.notifier).deleteTransaction(tx.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Transaction deleted')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(icon, color: color, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.merchant ?? tx.description ?? tx.type.displayName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${DateFormatter.formatShort(tx.date)}${tx.description != null ? " • ${tx.description}" : ""}',
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isIncome ? '+' : '-'}${CurrencyFormatter.format(tx.amount)}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(TransactionType? type, String label) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (val) {
          setState(() {
            _filterType = isSelected ? null : type;
          });
        },
      ),
    );
  }
}
