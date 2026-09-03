import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/merchant_categorizer.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/responsive.dart';

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

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const CsvImportModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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

  /// Parses `dd-MM-yyyy` (falls back to today only if the field can't be
  /// parsed at all, so the original statement date isn't silently discarded).
  DateTime? _parseDate(String raw) {
    final parts = raw.trim().split('-');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  int _skippedRows = 0;

  void _parseCsv() {
    final text = _csvController.text.trim();
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final List<ParsedCsvRow> parsed = [];
    int skipped = 0;

    for (var line in lines) {
      final parts = line.split(',');
      if (parts.length < 3) continue;

      // Skip header line
      if (parts[0].toLowerCase().contains('date')) continue;

      final desc = parts[1].trim();
      final amount = double.tryParse(parts[2].trim()) ?? 0.0;
      if (amount <= 0) {
        skipped++;
        continue;
      }

      final mapping = MerchantCategorizer.categorize(desc);
      final merchant = mapping?.merchantName ?? desc;
      final categoryId = mapping?.categoryId ?? 'cat_food';

      parsed.add(
        ParsedCsvRow(
          date: _parseDate(parts[0]) ?? DateTime.now(),
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
      _skippedRows = skipped;
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
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(financeNotifierProvider).accountsWithCalculatedBalances;
    if (!accounts.any((a) => a.id == _selectedAccountId)) {
      _selectedAccountId = accounts.isNotEmpty ? accounts.first.id : null;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 12,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CSV Statement Importer',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Text('Destination Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _selectedAccountId,
              dropdownColor: AppColors.surface,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
              ),
              items: accounts.map((acc) {
                return DropdownMenuItem(
                  value: acc.id,
                  child: Text(acc.name),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedAccountId = val),
            ),
            const SizedBox(height: 14),

            Text('Paste CSV / Bank Statement Text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _csvController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Date,Description,Amount\n22-08-2026,SWIGGY,780',
              ),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(LucideIcons.fileSpreadsheet, size: 18, color: AppColors.primary),
                label: Text('Parse & Preview Statement', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                onPressed: _parseCsv,
              ),
            ),
            const SizedBox(height: 16),

            if (_previewRows.isNotEmpty) ...[
              Text(
                'Detected Transactions (${_previewRows.length})',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              if (_skippedRows > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$_skippedRows row${_skippedRows > 1 ? 's' : ''} skipped (missing or non-positive amount)',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ],
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _previewRows.length,
                itemBuilder: (context, index) {
                  final row = _previewRows[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.merchantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('Auto Category: ${row.categoryId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '- ${CurrencyFormatter.format(row.amount)}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.expense, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _importAll,
                  child: Text('Import ${_previewRows.length} Transactions', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
