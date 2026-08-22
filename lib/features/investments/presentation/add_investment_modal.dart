import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';

class AddInvestmentModal extends ConsumerStatefulWidget {
  const AddInvestmentModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const AddInvestmentModal(),
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
            const Text(
              'Add Manual Investment / SIP',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Investment Name (e.g. Parag Parikh Flexi Cap)'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<InvestmentType>(
              value: _selectedType,
              dropdownColor: AppColors.surface,
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
                    decoration: const InputDecoration(labelText: 'Invested Amount (₹)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _currentValController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Current Value (₹)'),
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
                    decoration: const InputDecoration(labelText: 'Monthly SIP (₹) (Optional)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sipDayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'SIP Day (1-28)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveInvestment,
                child: const Text('Save Investment'),
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
        const SnackBar(content: Text('Please enter a valid investment name and invested amount')),
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
      const SnackBar(content: Text('Investment tracked successfully!'), backgroundColor: AppColors.income),
    );
  }
}
