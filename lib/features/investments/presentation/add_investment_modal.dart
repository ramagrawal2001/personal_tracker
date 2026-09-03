import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/responsive.dart';

class AddInvestmentModal extends ConsumerStatefulWidget {
  const AddInvestmentModal({super.key});

  static Future<void> show(BuildContext context) async {
    await AdaptiveModal.show(
      context: context,
      builder: (_) => const AddInvestmentModal(),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  @override
  ConsumerState<AddInvestmentModal> createState() => _AddInvestmentModalState();
}

class _AddInvestmentModalState extends ConsumerState<AddInvestmentModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _investedController = TextEditingController();
  final TextEditingController _currentValController = TextEditingController();
  final TextEditingController _sipController = TextEditingController();
  final TextEditingController _sipDayController = TextEditingController(text: '1');

  InvestmentType _selectedType = InvestmentType.mutualFundSip;

  @override
  void dispose() {
    _nameController.dispose();
    _investedController.dispose();
    _currentValController.dispose();
    _sipController.dispose();
    _sipDayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  'Add Asset / Investment',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Investment Name (e.g. Parag Parikh Flexi Cap)',
                prefixIcon: Icon(LucideIcons.trendingUp, size: 18),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<InvestmentType>(
              isExpanded: true,
              value: _selectedType,
              dropdownColor: AppColors.surface,
              decoration: const InputDecoration(
                labelText: 'Asset Category',
                prefixIcon: Icon(LucideIcons.pieChart, size: 18),
              ),
              items: InvestmentType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedType = val);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _investedController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Invested (${CurrencyFormatter.symbol})',
                      prefixText: '${CurrencyFormatter.symbol} ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _currentValController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Current Value (${CurrencyFormatter.symbol})',
                      prefixText: '${CurrencyFormatter.symbol} ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sipController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monthly SIP (${CurrencyFormatter.symbol}) (Optional)',
                      prefixText: '${CurrencyFormatter.symbol} ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sipDayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SIP Day (1-28)',
                      prefixIcon: Icon(LucideIcons.calendar, size: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveInvestment,
                child: const Text('Save Investment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveInvestment() {
    final name = _nameController.text.trim();
    final invested = double.tryParse(_investedController.text.trim()) ?? 0.0;
    final current = double.tryParse(_currentValController.text.trim()) ?? invested;
    final sip = double.tryParse(_sipController.text.trim()) ?? 0.0;
    final day = int.tryParse(_sipDayController.text.trim()) ?? 1;

    if (name.isEmpty || invested <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid investment name and invested amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    ref.read(financeNotifierProvider.notifier).addInvestment(
          name: name,
          type: _selectedType,
          investedAmount: invested,
          currentValue: current,
          monthlySipAmount: sip,
          sipDay: day,
        );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Investment saved successfully!'), backgroundColor: AppColors.income, behavior: SnackBarBehavior.floating),
    );
  }
}
