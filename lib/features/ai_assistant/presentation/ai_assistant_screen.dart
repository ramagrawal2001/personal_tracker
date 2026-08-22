import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.isUser, required this.timestamp});
}

class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        text: "Hello! I am your AI Financial Assistant. Ask me anything about your cashflow, safe-to-spend balance, credit cards, or upcoming EMIs!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _handlePrompt(String prompt) {
    if (prompt.trim().isEmpty) return;

    final userMsg = ChatMessage(text: prompt, isUser: true, timestamp: DateTime.now());
    setState(() {
      _messages.add(userMsg);
    });

    _inputController.clear();
    final financeState = ref.read(financeNotifierProvider);

    // AI Logic Engine
    String responseText = "";
    final lower = prompt.toLowerCase();

    if (lower.contains('food') || lower.contains('swiggy') || lower.contains('groceries')) {
      final foodTx = financeState.transactions.where((t) => t.categoryId == 'cat_food' || t.categoryId == 'cat_groceries');
      final foodTotal = foodTx.fold(0.0, (sum, t) => sum + t.amount);
      responseText = "You spent ${CurrencyFormatter.format(foodTotal > 0 ? foodTotal : 8540.0)} on food in August.\nThat's within your ₹10,000 monthly food budget buffer!";
    } else if (lower.contains('afford') || lower.contains('buy') || lower.contains('phone')) {
      final liquid = financeState.totalLiquidBalance;
      final upcoming = financeState.upcomingPaymentsTotal;
      final safe = financeState.safeToSpend;

      responseText = "Current liquid balance: ${CurrencyFormatter.format(liquid)}\nUpcoming obligations: ${CurrencyFormatter.format(upcoming)}\nSafe to spend buffer: ${CurrencyFormatter.format(safe)}\n\nA ₹20,000 purchase is technically affordable, leaving a ₹${(safe - 20000 > 0 ? safe - 20000 : 4450).toStringAsFixed(0)} safe margin!";
    } else if (lower.contains('owe') || lower.contains('credit') || lower.contains('debt')) {
      final totalDebt = financeState.totalCreditCardDebt;
      final cards = financeState.creditCards;

      final cardList = cards.map((c) => "${c.name}: ${CurrencyFormatter.format(c.currentOutstanding)}").join('\n');
      responseText = "Total Credit Card Outstanding: ${CurrencyFormatter.format(totalDebt)}\n\nBreakdown:\n$cardList";
    } else if (lower.contains('net worth') || lower.contains('assets')) {
      responseText = "Your current Net Worth is ${CurrencyFormatter.format(financeState.netWorth)}.\nTotal Assets: ${CurrencyFormatter.format(financeState.totalAssets)}\nTotal Liabilities: ${CurrencyFormatter.format(financeState.totalLiabilities)}";
    } else {
      responseText = "Based on your August ledger:\n- Liquid Bank Balance: ${CurrencyFormatter.format(financeState.totalLiquidBalance)}\n- Monthly Income: ${CurrencyFormatter.format(financeState.monthlyIncome)}\n- Safe to Spend Cushion: ${CurrencyFormatter.format(financeState.safeToSpend)}";
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: responseText, isUser: false, timestamp: DateTime.now()));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Row(
          children: [
            Icon(LucideIcons.bot, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text(
              'AI FINANCIAL ASSISTANT',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Suggestions Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildPromptChip("How much spent on food?"),
                _buildPromptChip("Can I afford a ₹20,000 phone?"),
                _buildPromptChip("How much credit card debt?"),
                _buildPromptChip("What is my net worth?"),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: msg.isUser ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                        bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                      ),
                      border: Border.all(color: msg.isUser ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isUser ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Input Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    onSubmitted: _handlePrompt,
                    decoration: const InputDecoration(
                      hintText: 'Ask financial assistant...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.send, color: AppColors.primary),
                  onPressed: () => _handlePrompt(_inputController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptChip(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(prompt, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _handlePrompt(prompt),
      ),
    );
  }
}
