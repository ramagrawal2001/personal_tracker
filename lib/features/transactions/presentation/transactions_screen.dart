import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../domain/models/models.dart';
import 'quick_add_modal.dart';

/// Sort orders offered on the Transactions list. [dateDesc] (newest first) is
/// the default — the list must never silently fall back to insertion order.
enum _SortOption { dateDesc, dateAsc, amountDesc, amountAsc, categoryAsc }

extension on _SortOption {
  String get label => switch (this) {
        _SortOption.dateDesc => 'Newest first',
        _SortOption.dateAsc => 'Oldest first',
        _SortOption.amountDesc => 'Amount: high to low',
        _SortOption.amountAsc => 'Amount: low to high',
        _SortOption.categoryAsc => 'Category (A–Z)',
      };
}

/// Quick date-range presets. [custom] defers to [_customRange].
enum _DatePreset { all, thisMonth, lastMonth, custom }

extension on _DatePreset {
  String get label => switch (this) {
        _DatePreset.all => 'All time',
        _DatePreset.thisMonth => 'This month',
        _DatePreset.lastMonth => 'Last month',
        _DatePreset.custom => 'Custom range',
      };
}

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  TransactionType? _filterType;
  _SortOption _sortOption = _SortOption.dateDesc;
  _DatePreset _datePreset = _DatePreset.all;
  DateTimeRange? _customRange;
  Set<String> _selectedCategoryIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTimeRange? get _activeRange {
    final now = DateTime.now();
    switch (_datePreset) {
      case _DatePreset.all:
        return null;
      case _DatePreset.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case _DatePreset.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        return DateTimeRange(start: lastMonth, end: DateTime(now.year, now.month, 1).subtract(const Duration(seconds: 1)));
      case _DatePreset.custom:
        return _customRange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final financeState = ref.watch(financeNotifierProvider);
    final query = _searchController.text.trim().toLowerCase();
    final range = _activeRange;

    final filtered = financeState.transactions.where((tx) {
      if (_filterType != null && tx.type != _filterType) return false;
      if (_selectedCategoryIds.isNotEmpty && !_selectedCategoryIds.contains(tx.categoryId)) return false;
      if (range != null && (tx.date.isBefore(range.start) || tx.date.isAfter(range.end))) return false;
      if (query.isNotEmpty) {
        final merchant = tx.merchant?.toLowerCase() ?? '';
        final desc = tx.description?.toLowerCase() ?? '';
        final notes = tx.notes?.toLowerCase() ?? '';
        final amountStr = tx.amount.toString();
        return merchant.contains(query) || desc.contains(query) || notes.contains(query) || amountStr.contains(query);
      }
      return true;
    }).toList();

    final categoriesById = {for (final c in financeState.categories) c.id: c};

    switch (_sortOption) {
      case _SortOption.dateDesc:
        filtered.sort((a, b) => b.date.compareTo(a.date));
        break;
      case _SortOption.dateAsc:
        filtered.sort((a, b) => a.date.compareTo(b.date));
        break;
      case _SortOption.amountDesc:
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case _SortOption.amountAsc:
        filtered.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case _SortOption.categoryAsc:
        filtered.sort((a, b) {
          final nameA = categoriesById[a.categoryId]?.name ?? '';
          final nameB = categoriesById[b.categoryId]?.name ?? '';
          final cmp = nameA.toLowerCase().compareTo(nameB.toLowerCase());
          return cmp != 0 ? cmp : b.date.compareTo(a.date);
        });
        break;
    }

    final hasActiveFilters = _datePreset != _DatePreset.all || _selectedCategoryIds.isNotEmpty;

    return AppScaffold(
      title: 'Transactions',
      actions: [
        IconButton(
          tooltip: 'Sort',
          icon: const Icon(LucideIcons.arrowDownUp, size: 20),
          onPressed: () => _showSortSheet(context),
        ),
        IconButton(
          tooltip: 'Filter',
          icon: Badge(
            isLabelVisible: hasActiveFilters,
            smallSize: 8,
            backgroundColor: AppColors.primary,
            child: const Icon(LucideIcons.slidersHorizontal, size: 20),
          ),
          onPressed: () => _showFilterSheet(context, financeState.categories),
        ),
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
          if (hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(LucideIcons.filter, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        if (_datePreset != _DatePreset.all) _datePreset.label,
                        if (_selectedCategoryIds.isNotEmpty) '${_selectedCategoryIds.length} categor${_selectedCategoryIds.length == 1 ? 'y' : 'ies'}',
                      ].join(' • '),
                      style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _datePreset = _DatePreset.all;
                      _customRange = null;
                      _selectedCategoryIds = {};
                    }),
                    child: Text('Clear', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
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
                        title: query.isNotEmpty || hasActiveFilters ? 'No matches found' : 'No transactions yet',
                        description: query.isNotEmpty || hasActiveFilters
                            ? 'Try a different search term or filter.'
                            : 'Tap + to record your first transaction.',
                        actionLabel: query.isEmpty && !hasActiveFilters ? 'Add Transaction' : null,
                        onAction: query.isEmpty && !hasActiveFilters ? () => QuickAddModal.show(context) : null,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildTransactionTile(filtered[index], categoriesById[filtered[index].categoryId]),
                  ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            for (final option in _SortOption.values)
              RadioListTile<_SortOption>(
                value: option,
                groupValue: _sortOption,
                activeColor: AppColors.primary,
                title: Text(option.label, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                onChanged: (val) {
                  if (val != null) setState(() => _sortOption = val);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, List<CategoryModel> categories) {
    var draftPreset = _datePreset;
    var draftRange = _customRange;
    var draftCategoryIds = {..._selectedCategoryIds};

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text('Filter', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setSheetState(() {
                          draftPreset = _DatePreset.all;
                          draftRange = null;
                          draftCategoryIds = {};
                        }),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Date range', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _DatePreset.values.map((preset) {
                            final isSelected = draftPreset == preset;
                            return ChoiceChip(
                              label: Text(preset.label),
                              selected: isSelected,
                              onSelected: (_) async {
                                if (preset == _DatePreset.custom) {
                                  final now = DateTime.now();
                                  final picked = await showDateRangePicker(
                                    context: ctx,
                                    firstDate: DateTime(now.year - 10),
                                    lastDate: now,
                                    initialDateRange: draftRange,
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      draftPreset = _DatePreset.custom;
                                      draftRange = picked;
                                    });
                                  }
                                } else {
                                  setSheetState(() => draftPreset = preset);
                                }
                              },
                              selectedColor: AppColors.primary.withValues(alpha: 0.2),
                              backgroundColor: AppColors.surfaceLight,
                              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                              labelStyle: TextStyle(color: isSelected ? AppColors.primary : AppColors.textSecondary, fontSize: 13),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        Text('Category', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        if (categories.isEmpty)
                          Text('No categories yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: categories.map((cat) {
                              final isSelected = draftCategoryIds.contains(cat.id);
                              return FilterChip(
                                avatar: Icon(iconForCategoryName(cat.icon), size: 14, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                                label: Text(cat.name),
                                selected: isSelected,
                                showCheckmark: false,
                                onSelected: (val) => setSheetState(() {
                                  if (val) {
                                    draftCategoryIds.add(cat.id);
                                  } else {
                                    draftCategoryIds.remove(cat.id);
                                  }
                                }),
                                selectedColor: AppColors.primary.withValues(alpha: 0.2),
                                backgroundColor: AppColors.surfaceLight,
                                side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                                labelStyle: TextStyle(color: isSelected ? AppColors.primary : AppColors.textSecondary, fontSize: 13),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        setState(() {
                          _datePreset = draftPreset;
                          _customRange = draftRange;
                          _selectedCategoryIds = draftCategoryIds;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('Apply', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionTile(TransactionModel tx, CategoryModel? category) {
    final isIncome = tx.type == TransactionType.income || tx.type == TransactionType.refund;
    final isTransfer = tx.type == TransactionType.transfer ||
        tx.type == TransactionType.creditCardPayment ||
        tx.type == TransactionType.loanPayment;

    final color = isIncome ? AppColors.income : isTransfer ? AppColors.transfer : AppColors.expense;
    final icon = isIncome ? LucideIcons.arrowDownLeft : isTransfer ? LucideIcons.arrowRightLeft : LucideIcons.arrowUpRight;
    final categoryColor = category != null ? Color(int.parse(category.colorHex)) : AppColors.textMuted;

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
      onDismissed: (_) async {
        // The swipe animation has already removed this row from view; on a
        // failed delete the transaction stays in state and reappears on the
        // next rebuild — surfaced via the error SnackBar below.
        // Captured as a local so the `mounted` narrowing below actually
        // applies — `context` is `State.context`, a getter, and the
        // analyzer can't promote across separate getter reads.
        final screenContext = context;
        Object? failure;
        try {
          await ref.read(financeNotifierProvider.notifier).deleteTransaction(tx.id);
        } catch (e) {
          failure = e;
        }
        if (!screenContext.mounted) return;
        ScaffoldMessenger.of(screenContext).showSnackBar(failure == null
            ? const SnackBar(content: Text('Transaction deleted'))
            : SnackBar(content: Text('Delete failed: $failure'), backgroundColor: AppColors.expense));
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (category != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(iconForCategoryName(category.icon), size: 10, color: categoryColor),
                              const SizedBox(width: 3),
                              Text(category.name, style: TextStyle(color: categoryColor, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          '${DateFormatter.formatShort(tx.date)}${tx.description != null ? " • ${tx.description}" : ""}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    ],
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
