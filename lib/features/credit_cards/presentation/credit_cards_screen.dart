import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/models/models.dart';
import '../../transactions/presentation/quick_add_modal.dart';

// ─── Main Screen ──────────────────────────────────────────────────────────────
class CreditCardsScreen extends ConsumerStatefulWidget {
  const CreditCardsScreen({super.key});
  @override
  ConsumerState<CreditCardsScreen> createState() => _CreditCardsScreenState();
}

class _CreditCardsScreenState extends ConsumerState<CreditCardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _carouselIndex = 0;
  final _pageController = PageController(viewportFraction: 0.88);

  static const _tabs = [
    ('All', null),
    ('Credit', CardType.credit),
    ('Debit', CardType.debit),
    ('Prepaid', CardType.prepaid),
    ('Store', CardType.store),
    ('Forex', CardType.forex),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeNotifierProvider);
    final allCards = state.creditCards;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            pinned: true,
            floating: true,
            title: const Text(
              'Cards Vault',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.plus, color: AppColors.primary, size: 20),
                ),
                onPressed: () => _showAddCardModal(context),
              ),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            final filtered = tab.$2 == null
                ? allCards
                : allCards.where((c) => c.cardType == tab.$2).toList();
            return _buildTabContent(filtered, allCards);
          }).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _showAddCardModal(context),
        icon: const Icon(LucideIcons.plus, color: Colors.white, size: 18),
        label: const Text('Add Card', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildTabContent(List<CardModel> cards, List<CardModel> allCards) {
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: EmptyState(
            icon: LucideIcons.creditCard,
            title: 'No Cards Yet',
            description: 'Add your credit, debit, prepaid, store, or forex cards to track them securely.',
            actionLabel: 'Add Your First Card',
            onAction: () => _showAddCardModal(context),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // ── Swipeable Card Carousel ──
          SizedBox(
            height: 210,
            child: PageView.builder(
              controller: _pageController,
              itemCount: cards.length,
              onPageChanged: (i) => setState(() => _carouselIndex = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _GlassCard(card: cards[i]),
              ),
            ),
          ),

          // ── Carousel dots ──
          if (cards.length > 1) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(cards.length, (i) {
                final active = i == _carouselIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],

          const SizedBox(height: 24),

          // ── Summary banner ──
          _buildSummaryBanner(cards),

          const SizedBox(height: 24),

          // ── Card list ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Your Cards'),
                ...cards.map((c) => _CardListTile(
                  card: c,
                  onPayBill: () => QuickAddModal.show(context, initialType: TransactionType.creditCardPayment, initialCreditCardId: c.id),
                  onEdit: () => _showEditCardSheet(c),
                  onDelete: () => _confirmDelete(c),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(List<CardModel> cards) {
    final creditCards = cards.where((c) => c.cardType == CardType.credit).toList();
    final totalLimit = creditCards.fold(0.0, (s, c) => s + c.creditLimit);
    final totalUsed = creditCards.fold(0.0, (s, c) => s + c.currentOutstanding);
    final utilPct = totalLimit > 0 ? (totalUsed / totalLimit * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppDecorations.card(radius: AppDecorations.radiusLg),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SummaryItem(
                  label: 'Total Cards',
                  value: '${cards.length}',
                  icon: LucideIcons.creditCard,
                  color: AppColors.primary,
                ),
                if (creditCards.isNotEmpty) _SummaryItem(
                  label: 'Credit Used',
                  value: CurrencyFormatter.format(totalUsed),
                  icon: LucideIcons.arrowUpRight,
                  color: AppColors.expense,
                ),
                if (creditCards.isNotEmpty) _SummaryItem(
                  label: 'Available',
                  value: CurrencyFormatter.format(totalLimit - totalUsed),
                  icon: LucideIcons.shieldCheck,
                  color: AppColors.income,
                ),
              ],
            ),
            if (creditCards.isNotEmpty && totalLimit > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Credit Utilization', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  Text(
                    '${utilPct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: utilPct > 30 ? AppColors.warning : AppColors.income,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (utilPct / 100).clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceLight,
                  valueColor: AlwaysStoppedAnimation(utilPct > 30 ? AppColors.warning : AppColors.income),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddCardModal(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCardModal(),
    );
  }

  void _showEditCardSheet(CardModel card) {
    final nameCtrl = TextEditingController(text: card.name);
    final bankCtrl = TextEditingController(text: card.bank);
    final holderCtrl = TextEditingController(text: card.cardholderName);
    final limitCtrl = TextEditingController(text: card.creditLimit.toStringAsFixed(0));
    final statementDayCtrl = TextEditingController(text: '${card.statementDay}');
    final dueDayCtrl = TextEditingController(text: '${card.dueDay}');
    final isCredit = card.cardType == CardType.credit;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Edit Card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Card Name')),
                const SizedBox(height: 12),
                TextField(controller: bankCtrl, decoration: const InputDecoration(labelText: 'Bank / Issuer')),
                const SizedBox(height: 12),
                TextField(controller: holderCtrl, decoration: const InputDecoration(labelText: 'Cardholder Name')),
                if (isCredit) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: limitCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Credit Limit (${CurrencyFormatter.symbol})'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: statementDayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Statement Day'))),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: dueDayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Due Day (1-31)')),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.expense, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (nameCtrl.text.trim().isEmpty || bankCtrl.text.trim().isEmpty) {
                        setSheetState(() => error = 'Name and bank are required');
                        return;
                      }
                      double? limit;
                      int? statementDay;
                      int? dueDay;
                      if (isCredit) {
                        limit = double.tryParse(limitCtrl.text);
                        statementDay = int.tryParse(statementDayCtrl.text);
                        dueDay = int.tryParse(dueDayCtrl.text);
                        if (limit == null || limit < 0) {
                          setSheetState(() => error = 'Enter a valid credit limit');
                          return;
                        }
                        if (statementDay == null || statementDay < 1 || statementDay > 31) {
                          setSheetState(() => error = 'Statement day must be between 1 and 31');
                          return;
                        }
                        if (dueDay == null || dueDay < 1 || dueDay > 31) {
                          setSheetState(() => error = 'Due day must be between 1 and 31');
                          return;
                        }
                      }
                      ref.read(financeNotifierProvider.notifier).updateCard(
                        card.id,
                        name: nameCtrl.text.trim(),
                        bank: bankCtrl.text.trim(),
                        cardholderName: holderCtrl.text.trim(),
                        creditLimit: limit,
                        statementDay: statementDay,
                        dueDay: dueDay,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('Save Changes'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(CardModel card) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Card?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove ${card.name} (•••• ${card.last4}) from your vault?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.expense,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              ref.read(financeNotifierProvider.notifier).deleteCard(card.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${card.name} removed'), backgroundColor: AppColors.expense),
              );
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ─── Glass Card Widget ────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final CardModel card;
  const _GlassCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final colors = card.colorPreset.gradientColors.map((c) => Color(c)).toList();

    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),

          // Chip graphic
          Positioned(
            left: 24,
            top: 60,
            child: _ChipGraphic(),
          ),

          // Network logo (top right)
          Positioned(
            right: 20,
            top: 20,
            child: _NetworkBadge(network: card.network),
          ),

          // Card type badge (top left)
          Positioned(
            left: 20,
            top: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (card.isVirtual) ...[
                    const Icon(LucideIcons.wifi, size: 10, color: Colors.white),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    card.isVirtual ? 'Virtual ${card.cardType.displayName}' : card.cardType.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

          // Card number + name (bottom)
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•••• •••• •••• ${card.last4}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CARD HOLDER',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9, letterSpacing: 1),
                        ),
                        Text(
                          card.cardholderName.isEmpty ? card.bank : card.cardholderName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'EXPIRES',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9, letterSpacing: 1),
                        ),
                        Text(
                          card.expiryDisplay,
                          style: TextStyle(
                            color: card.isExpired ? Colors.red[300] : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipGraphic extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 30,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD4B483), Color(0xFFB8943A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(painter: _ChipPainter()),
    );
  }
}

class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(size.width * 0.5, 0), Offset(size.width * 0.5, size.height), paint);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.25, size.height * 0.2, size.width * 0.5, size.height * 0.6),
        const Radius.circular(3),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _NetworkBadge extends StatelessWidget {
  final CardNetwork network;
  const _NetworkBadge({required this.network});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        network.displayName,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}

// ─── Card List Tile ───────────────────────────────────────────────────────────
class _CardListTile extends StatelessWidget {
  final CardModel card;
  final VoidCallback onPayBill;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CardListTile({required this.card, required this.onPayBill, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = card.colorPreset.gradientColors.map((c) => Color(c)).toList();
    final isCredit = card.cardType == CardType.credit;
    final hasFunds = (card.balance ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(radius: AppDecorations.radiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Color indicator strip
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.first, colors.last],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(card.cardType.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            card.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (card.isExpired)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.expense.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'EXPIRED',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.expense,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${card.bank}  •  ${card.network.displayName}  •  •••• ${card.last4}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                itemBuilder: (_) => [
                  if (isCredit)
                    const PopupMenuItem(
                      value: 'pay',
                      child: Row(
                        children: [
                          Icon(LucideIcons.arrowRightLeft, size: 14, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Pay Bill', style: TextStyle(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(LucideIcons.pencil, size: 14, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2, size: 14, color: AppColors.expense),
                        SizedBox(width: 8),
                        Text('Remove', style: TextStyle(color: AppColors.expense)),
                      ],
                    ),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'pay') {
                    onPayBill();
                  } else if (v == 'edit') {
                    onEdit();
                  } else {
                    onDelete();
                  }
                },
              ),
            ],
          ),

          if (isCredit && card.creditLimit > 0) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoChip(
                  label: 'Outstanding',
                  value: CurrencyFormatter.format(card.currentOutstanding),
                  valueColor: AppColors.expense,
                ),
                _InfoChip(
                  label: 'Available',
                  value: CurrencyFormatter.format(card.availableLimit),
                  valueColor: AppColors.income,
                ),
                _InfoChip(
                  label: 'Limit',
                  value: CurrencyFormatter.format(card.creditLimit),
                  valueColor: AppColors.textPrimary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (card.utilizationPercentage / 100).clamp(0, 1),
                minHeight: 5,
                backgroundColor: AppColors.surfaceLight,
                valueColor: AlwaysStoppedAnimation(card.utilizationPercentage > 30 ? AppColors.warning : AppColors.income),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stmt: ${card.statementDay}th  •  Due: ${card.dueDay}th',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                GestureDetector(
                  onTap: onPayBill,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Pay Bill',
                      style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if ((card.cardType == CardType.prepaid || card.cardType == CardType.forex) && hasFunds) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(LucideIcons.wallet, size: 14, color: AppColors.income),
                const SizedBox(width: 6),
                const Text('Balance: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Text(
                  card.currency != null && card.currency != 'INR'
                      ? '${card.currency} ${card.balance!.toStringAsFixed(2)}'
                      : CurrencyFormatter.format(card.balance!),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.income),
                ),
              ],
            ),
          ],

          if (card.expiryDisplay != '——') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  LucideIcons.calendar,
                  size: 12,
                  color: card.isExpired ? AppColors.expense : AppColors.textMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  card.isExpired ? 'Expired ${card.expiryDisplay}' : 'Expires ${card.expiryDisplay}',
                  style: TextStyle(
                    fontSize: 11,
                    color: card.isExpired ? AppColors.expense : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  const _InfoChip({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor)),
    ],
  );
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SummaryItem({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: AppDecorations.iconBadge(color, circle: true),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ],
  );
}

// ─── Add Card Modal ───────────────────────────────────────────────────────────
class _AddCardModal extends ConsumerStatefulWidget {
  const _AddCardModal();
  @override
  ConsumerState<_AddCardModal> createState() => _AddCardModalState();
}

class _AddCardModalState extends ConsumerState<_AddCardModal> {
  CardType _selectedType = CardType.credit;
  CardNetwork _selectedNetwork = CardNetwork.visa;
  CardColorPreset _selectedColor = CardColorPreset.midnight;

  final _nameCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _last4Ctrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'USD');

  int? _expiryMonth;
  int? _expiryYear;
  int _statementDay = 1;
  int _dueDay = 15;
  bool _isVirtual = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _bankCtrl, _last4Ctrl, _holderCtrl, _limitCtrl, _balanceCtrl, _notesCtrl, _currencyCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add New Card',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),

            Expanded(
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 100),
                children: [
                  // Card type selector
                  const Text('Card Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  _buildTypeSelector(),
                  const SizedBox(height: 20),

                  // Preview mini card
                  _buildMiniPreview(),
                  const SizedBox(height: 24),

                  // Common fields
                  _field(_nameCtrl, 'Card Name', hint: 'e.g. HDFC Regalia', icon: LucideIcons.creditCard),
                  const SizedBox(height: 12),
                  _field(_bankCtrl, 'Bank / Issuer', hint: 'e.g. HDFC Bank', icon: LucideIcons.building2),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          _last4Ctrl,
                          'Last 4 Digits',
                          hint: '1234',
                          icon: LucideIcons.hash,
                          inputType: TextInputType.number,
                          formatter: FilteringTextInputFormatter.digitsOnly,
                          maxLen: 4,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_holderCtrl, 'Cardholder Name', hint: 'Your Name', icon: LucideIcons.user)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Network
                  const Text('Network', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  _buildNetworkSelector(),
                  const SizedBox(height: 12),

                  // Expiry
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown<int?>(
                          label: 'Expiry Month',
                          value: _expiryMonth,
                          items: [null, ...List.generate(12, (i) => i + 1)],
                          display: (v) => v == null ? '—' : v.toString().padLeft(2, '0'),
                          onChanged: (v) => setState(() => _expiryMonth = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdown<int?>(
                          label: 'Expiry Year',
                          value: _expiryYear,
                          items: [null, ...List.generate(12, (i) => DateTime.now().year + i)],
                          display: (v) => v == null ? '—' : v.toString(),
                          onChanged: (v) => setState(() => _expiryYear = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Credit-card-specific
                  if (_selectedType == CardType.credit) ...[
                    _field(
                      _limitCtrl,
                    'Credit Limit (${CurrencyFormatter.symbol})',
                      hint: '100000',
                      icon: LucideIcons.trendingUp,
                      inputType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdown<int>(
                            label: 'Statement Day',
                            value: _statementDay,
                            items: List.generate(28, (i) => i + 1),
                            display: (v) => '${v}th',
                            onChanged: (v) {
                              if (v != null) setState(() => _statementDay = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDropdown<int>(
                            label: 'Due Day',
                            value: _dueDay,
                            items: List.generate(28, (i) => i + 1),
                            display: (v) => '${v}th',
                            onChanged: (v) {
                              if (v != null) setState(() => _dueDay = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Prepaid / forex balance
                  if (_selectedType == CardType.prepaid || _selectedType == CardType.forex) ...[
                    _field(
                      _balanceCtrl,
                      'Current Balance',
                      hint: '5000',
                      icon: LucideIcons.wallet,
                      inputType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    if (_selectedType == CardType.forex) ...[
                      _field(_currencyCtrl, 'Currency Code', hint: 'USD, EUR, GBP…', icon: LucideIcons.globe),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // Virtual toggle
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.wifi, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Virtual Card', style: TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                              Text('No physical card issued', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isVirtual,
                          onChanged: (v) => setState(() => _isVirtual = v),
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Card color
                  const Text('Card Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  _buildColorSelector(),
                  const SizedBox(height: 12),

                  // Notes
                  _field(
                    _notesCtrl,
                    'Notes / Hints (Optional)',
                    hint: 'PIN hint, portal URL…',
                    icon: LucideIcons.stickyNote,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 28),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Add Card to Vault', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPreview() {
    final colors = _selectedColor.gradientColors.map((c) => Color(c)).toList();
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _nameCtrl.text.isEmpty ? 'Card Name' : _nameCtrl.text,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  _last4Ctrl.text.length == 4 ? '•••• ${_last4Ctrl.text}' : '•••• ••••',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, letterSpacing: 1.5),
                ),
              ],
            ),
            Text(
              _selectedNetwork.displayName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: CardType.values.map((type) {
          final selected = type == _selectedType;
          return GestureDetector(
            onTap: () => setState(() => _selectedType = type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? AppColors.primary : AppColors.border),
              ),
              child: Row(
                children: [
                  Text(type.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    type.displayName,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNetworkSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: CardNetwork.values.map((net) {
          final selected = net == _selectedNetwork;
          return GestureDetector(
            onTap: () => setState(() => _selectedNetwork = net),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
              ),
              child: Text(
                net.displayName,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildColorSelector() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: CardColorPreset.values.map((preset) {
          final selected = preset == _selectedColor;
          final colors = preset.gradientColors.map((c) => Color(c)).toList();
          return GestureDetector(
            onTap: () => setState(() => _selectedColor = preset),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
                boxShadow: selected ? [BoxShadow(color: colors.last.withValues(alpha: 0.5), blurRadius: 8)] : null,
              ),
              child: selected ? const Icon(LucideIcons.check, color: Colors.white, size: 16) : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) display,
    required void Function(T?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButton<T>(
            value: value,
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(display(i), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)))).toList(),
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.surface,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String hint = '',
    IconData? icon,
    TextInputType inputType = TextInputType.text,
    TextInputFormatter? formatter,
    int maxLen = 200,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      maxLength: maxLen,
      maxLines: maxLines,
      inputFormatters: formatter != null ? [formatter] : null,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 16, color: AppColors.textMuted) : null,
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty || _bankCtrl.text.trim().isEmpty || _last4Ctrl.text.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill card name, bank, and last 4 digits'), backgroundColor: AppColors.expense),
      );
      return;
    }
    final limit = double.tryParse(_limitCtrl.text) ?? 0;
    if (limit < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credit limit cannot be negative'), backgroundColor: AppColors.expense),
      );
      return;
    }
    final balance = double.tryParse(_balanceCtrl.text);
    if (balance != null && balance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balance cannot be negative'), backgroundColor: AppColors.expense),
      );
      return;
    }
    setState(() => _saving = true);

    ref.read(financeNotifierProvider.notifier).addCard(
      cardType: _selectedType,
      name: _nameCtrl.text.trim(),
      bank: _bankCtrl.text.trim(),
      last4: _last4Ctrl.text.trim(),
      cardholderName: _holderCtrl.text.trim(),
      network: _selectedNetwork,
      expiryMonth: _expiryMonth,
      expiryYear: _expiryYear,
      colorPreset: _selectedColor,
      isVirtual: _isVirtual,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      creditLimit: double.tryParse(_limitCtrl.text) ?? 0,
      statementDay: _statementDay,
      dueDay: _dueDay,
      balance: double.tryParse(_balanceCtrl.text),
      currency: _selectedType == CardType.forex ? _currencyCtrl.text.trim().toUpperCase() : null,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text('${_nameCtrl.text} added to vault!'),
          ],
        ),
        backgroundColor: AppColors.income,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
