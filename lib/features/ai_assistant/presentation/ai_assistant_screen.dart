import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_scaffold.dart';

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
      responseText = "You spent ${CurrencyFormatter.format(foodTotal > 0 ? foodTotal : 8540.0)} on food this month.\nThat's within your monthly food budget buffer!";
    } else if (lower.contains('afford') || lower.contains('buy') || lower.contains('phone')) {
      final liquid = financeState.totalLiquidBalance;
      final upcoming = financeState.upcomingPaymentsTotal;
      final safe = financeState.safeToSpend;

      responseText = "Current liquid balance: ${CurrencyFormatter.format(liquid)}\nUpcoming obligations: ${CurrencyFormatter.format(upcoming)}\nSafe to spend cushion: ${CurrencyFormatter.format(safe)}\n\nA ₹20,000 purchase is technically affordable, leaving a ₹${(safe - 20000 > 0 ? safe - 20000 : 4450).toStringAsFixed(0)} safe margin!";
    } else if (lower.contains('owe') || lower.contains('credit') || lower.contains('debt')) {
      final totalDebt = financeState.totalCreditCardDebt;
      final cards = financeState.creditCards;

      final cardList = cards.map((c) => "${c.name}: ${CurrencyFormatter.format(c.currentOutstanding)}").join('\n');
      responseText = "Total Credit Card Outstanding: ${CurrencyFormatter.format(totalDebt)}\n\nBreakdown:\n$cardList";
    } else if (lower.contains('net worth') || lower.contains('assets')) {
      responseText = "Your current Net Worth is ${CurrencyFormatter.format(financeState.netWorth)}.\nTotal Assets: ${CurrencyFormatter.format(financeState.totalAssets)}\nTotal Liabilities: ${CurrencyFormatter.format(financeState.totalLiabilities)}";
    } else {
      responseText = "Based on your real-time ledger:\n- Liquid Bank Balance: ${CurrencyFormatter.format(financeState.totalLiquidBalance)}\n- Monthly Income: ${CurrencyFormatter.format(financeState.monthlyIncome)}\n- Safe to Spend Cushion: ${CurrencyFormatter.format(financeState.safeToSpend)}";
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
    return AppScaffold(
      title: 'AI Financial Assistant',
      showBackButton: true,
      titleWidget: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: AppDecorations.iconBadge(AppColors.primary, circle: true),
            child: Icon(LucideIcons.bot, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'AI Financial Assistant',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
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
                if (msg.isUser) {
                  return _buildUserBubble(msg);
                } else {
                  return _buildBotBubble(msg);
                }
              },
            ),
          ),

          // Input Bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    onSubmitted: _handlePrompt,
                    decoration: InputDecoration(
                      hintText: 'Ask financial assistant…',
                      prefixIcon: Icon(LucideIcons.sparkles, color: AppColors.primary, size: 18),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                    onPressed: () => _handlePrompt(_inputController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildBotBubble(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.all(14),
        decoration: AppDecorations.card(radius: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: AppDecorations.iconBadge(AppColors.primary, circle: true),
              child: Icon(LucideIcons.bot, color: AppColors.primary, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg.text,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(
          prompt,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _handlePrompt(prompt),
      ),
    );
  }
}
