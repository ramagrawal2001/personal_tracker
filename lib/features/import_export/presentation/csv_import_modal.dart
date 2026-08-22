import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/merchant_categorizer.dart';
import '../../../core/utils/currency_formatter.dart';

class ParsedCsvRow {
  final DateTime date;
  final String rawDescription;
  final String merchantName;
  final double amount;
  final String categoryId;
  final TransactionType type;

  ParsedCsvRow({
    required this.date,
    required this.rawDescription,
    required this.merchantName,
    required this.amount,
    required this.categoryId,
    required this.type,
  });
}

class CsvImportModal extends ConsumerStatefulWidget {
  const CsvImportModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const CsvImportModal(),
    );
  }

  @override
  ConsumerState<CsvImportModal> createState() => _CsvImportModalState();
}

class _CsvImportModalState extends ConsumerState<CsvImportModal> {
  final TextEditingController _csvController = TextEditingController(
    text: "Date,Description,Amount\n22-08-2026,SWIGGY,780\n21-08-2026,AMAZON,2450\n20-08-2026,SHELL PETROL,3000",
  );

  String? _selectedAccountId;
  List<ParsedCsvRow> _previewRows = [];

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  void _parseCsv() {
    final text = _csvController.text.trim();
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final List<ParsedCsvRow> parsed = [];

    for (var line in lines) {
      final parts = line.split(',');
      if (parts.length < 3) continue;

      // Skip header line
      if (parts[0].toLowerCase().contains('date')) continue;

      final desc = parts[1].trim();
      final amount = double.tryParse(parts[2].trim()) ?? 0.0;
      if (amount <= 0) continue;

      final mapping = MerchantCategorizer.categorize(desc);
      final merchant = mapping?.merchantName ?? desc;
      final categoryId = mapping?.categoryId ?? 'cat_food';

      parsed.add(
        ParsedCsvRow(
          date: DateTime.now(),
          rawDescription: desc,
          merchantName: merchant,
          amount: amount,
          categoryId: categoryId,
          type: TransactionType.expense,
        ),
      );
    }

    setState(() {
      _previewRows = parsed;
    });
  }

  void _importAll() {
    if (_selectedAccountId == null || _previewRows.isEmpty) return;

    final notifier = ref.read(financeNotifierProvider.notifier);
    for (var row in _previewRows) {
      notifier.addTransaction(
        accountId: _selectedAccountId!,
        type: row.type,
        amount: row.amount,
        categoryId: row.categoryId,
        merchant: row.merchantName,
        date: row.date,
        description: 'CSV Import: ${row.rawDescription}',
      );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully imported ${_previewRows.length} transactions!'),
        backgroundColor: AppColors.income,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(financeNotifierProvider).accountsWithCalculatedBalances;
    if (_selectedAccountId == null && accounts.isNotEmpty) {
      _selectedAccountId = accounts.first.id;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CSV Statement Importer',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            const Text('Destination Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedAccountId,
              dropdownColor: AppColors.surface,
              items: accounts.map((acc) {
                return DropdownMenuItem(
                  value: acc.id,
                  child: Text(acc.name),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedAccountId = val),
            ),
            const SizedBox(height: 14),

            const Text('Paste CSV / Bank Statement Text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _csvController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Date,Description,Amount\n22-08-2026,SWIGGY,780',
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(LucideIcons.fileSpreadsheet, size: 18),
                label: const Text('Parse & Preview Statement'),
                onPressed: _parseCsv,
              ),
            ),
            const SizedBox(height: 16),

            if (_previewRows.isNotEmpty) ...[
              Text(
                'Detected Transactions (${_previewRows.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _previewRows.length,
                itemBuilder: (context, index) {
                  final row = _previewRows[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.merchantName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 13)),
                            Text('Auto Category: ${row.categoryId}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                        Text(
                          '- ${CurrencyFormatter.format(row.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.expense, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _importAll,
                  child: Text('Import ${_previewRows.length} Transactions'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
