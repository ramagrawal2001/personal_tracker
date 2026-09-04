import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/secret_cipher_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/secret_reveal_sheet.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../../../domain/models/models.dart';
import '../../transactions/presentation/quick_add_modal.dart';

/// Parses a `0xAARRGGBB` / `#RRGGBB` / `RRGGBB` colour string.
Color? parseCardHex(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
  if (s.length == 6) s = 'FF$s';
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(v);
}

/// `0xAARRGGBB` string for a [Color], without touching the deprecated `.value`.
String cardHexOf(Color c) {
  int ch(double x) => (x * 255).round().clamp(0, 255);
  final argb = (ch(c.a) << 24) | (ch(c.r) << 16) | (ch(c.g) << 8) | ch(c.b);
  return '0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

/// A 3-stop gradient built from the card's free-form [CardModel.colorHex] when
/// set (hsl darken 12% → base → hsl lighten 10%), else the preset gradient.
List<Color> cardGradientColors(CardModel card) {
  final base = parseCardHex(card.colorHex);
  if (base != null) {
    final hsl = HSLColor.fromColor(base);
    return [
      hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor(),
      base,
      hsl.withLightness((hsl.lightness + 0.10).clamp(0.0, 1.0)).toColor(),
    ];
  }
  return card.colorPreset.gradientColors.map((c) => Color(c)).toList();
}

/// White or near-black foreground for text laid over [gradient], by luminance.
Color cardForeground(List<Color> gradient) {
  final mid = gradient[gradient.length ~/ 2];
  return mid.computeLuminance() > 0.55 ? const Color(0xFF14142B) : Colors.white;
}

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
            title: Text(
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
                  child: Icon(LucideIcons.plus, color: AppColors.primary, size: 20),
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
          _ResponsiveCardCarousel(cards: cards, onPageChanged: (i) => setState(() => _carouselIndex = i)),
          // ── Carousel dots ──
          if (cards.length > 1) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(cards.length, (i) {
                final active = i == _carouselIndex;
                final disableAnimations = MediaQuery.of(context).disableAnimations;
                return AnimatedContainer(
                  duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 250),
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
            padding: EdgeInsets.symmetric(horizontal: context.responsiveHorizontalPadding()),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Your Cards'),
                ...cards.map((c) {
                  AccountModel? linked;
                  if (c.linkedAccountId != null) {
                    for (final a in ref.read(financeNotifierProvider).accountsWithCalculatedBalances) {
                      if (a.id == c.linkedAccountId && !a.isDeleted) {
                        linked = a;
                        break;
                      }
                    }
                  }
                  return _CardListTile(
                    card: c,
                    linkedAccount: linked,
                    onPayBill: () => QuickAddModal.show(context, initialType: TransactionType.creditCardPayment, initialCreditCardId: c.id),
                    onEdit: () => _showEditCardSheet(c),
                    onDelete: () => _confirmDelete(c),
                    onViewSecrets: () => _showCardSecrets(c),
                  );
                }),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: 'Total Cards',
                    value: '${cards.length}',
                    icon: LucideIcons.creditCard,
                    color: AppColors.primary,
                  ),
                ),
                if (creditCards.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryItem(
                      label: 'Credit Used',
                      value: CurrencyFormatter.format(totalUsed),
                      icon: LucideIcons.arrowUpRight,
                      color: AppColors.expense,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryItem(
                      label: 'Available',
                      value: CurrencyFormatter.format(totalLimit - totalUsed),
                      icon: LucideIcons.shieldCheck,
                      color: AppColors.income,
                    ),
                  ),
                ],
              ],
            ),
            if (creditCards.isNotEmpty && totalLimit > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Credit Utilization', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
    AdaptiveModal.show(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCardModal(),
    );
  }

  void _showCardSecrets(CardModel card) {
    AdaptiveModal.show(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CardSecretsSheet(card: card),
    );
  }

  void _showEditCardSheet(CardModel card) {
    final nameCtrl = TextEditingController(text: card.name);
    final bankCtrl = TextEditingController(text: card.bank);
    final holderCtrl = TextEditingController(text: card.cardholderName);
    final limitCtrl = TextEditingController(text: card.creditLimit.toStringAsFixed(0));
    final statementDayCtrl = TextEditingController(text: '${card.statementDay}');
    final dueDayCtrl = TextEditingController(text: '${card.dueDay}');
    final numCtrl = TextEditingController();
    final cvvCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final isCredit = card.cardType == CardType.credit;
    final isDebit = card.cardType == CardType.debit;
    final linkableAccounts = ref
        .read(financeNotifierProvider)
        .accountsWithCalculatedBalances
        .where((a) => !a.isDeleted)
        .toList();
    String? linkedAccountId = linkableAccounts.any((a) => a.id == card.linkedAccountId)
        ? card.linkedAccountId
        : null;
    String? colorHex = card.colorHex;
    String? error;

    AdaptiveModal.show(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Edit Card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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
                if (isDebit) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(LucideIcons.building2, size: 13, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Linked bank account — purchases deduct from it',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (linkableAccounts.isEmpty)
                    Text('Add a bank account first — a debit card must be linked to one.',
                        style: TextStyle(fontSize: 12, color: AppColors.expense))
                  else
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: linkedAccountId,
                      dropdownColor: AppColors.surface,
                      hint: Text('Select an account', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                      ),
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      items: linkableAccounts.map((a) {
                        final l4 = (a.accountNumberLast4 != null && a.accountNumberLast4!.isNotEmpty)
                            ? '  ••••${a.accountNumberLast4}'
                            : '';
                        return DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.name} · ${a.type.displayName}$l4', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => setSheetState(() => linkedAccountId = v),
                    ),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Icon(LucideIcons.lock, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(card.encCardNumber != null ? 'Replace sensitive details' : 'Add sensitive details',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: numCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 19,
                  decoration: const InputDecoration(labelText: 'Card Number (leave blank to keep)', counterText: ''),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: cvvCtrl, obscureText: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 4, decoration: const InputDecoration(labelText: 'CVV', counterText: ''))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: pinCtrl, obscureText: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 6, decoration: const InputDecoration(labelText: 'ATM PIN', counterText: ''))),
                ]),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(LucideIcons.palette, size: 15, color: AppColors.primary),
                    label: Text(colorHex != null ? 'Custom colour set — change' : 'Pick a custom colour',
                        style: TextStyle(color: AppColors.primary, fontSize: 13)),
                    onPressed: () async {
                      Color picked = parseCardHex(colorHex) ?? const Color(0xFF3B82F6);
                      final result = await showDialog<Color>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          title: Text('Pick a card colour', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                          content: SingleChildScrollView(
                            child: ColorPicker(
                              pickerColor: picked,
                              onColorChanged: (c) => picked = c,
                              enableAlpha: false,
                              paletteType: PaletteType.hueWheel,
                              labelTypes: const [],
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                            ElevatedButton(onPressed: () => Navigator.pop(dctx, picked), child: const Text('Use colour')),
                          ],
                        ),
                      );
                      if (result != null) setSheetState(() => colorHex = cardHexOf(result));
                    },
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: AppColors.expense, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      if (nameCtrl.text.trim().isEmpty || bankCtrl.text.trim().isEmpty) {
                        setSheetState(() => error = 'Name and bank are required');
                        return;
                      }
                      if (isDebit && linkedAccountId == null) {
                        setSheetState(() => error = 'Select the bank account this debit card draws from');
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
                      final rawNum = numCtrl.text.replaceAll(RegExp(r'\D'), '');
                      String? encNum, encCvv, encPin, newLast4;
                      if (rawNum.isNotEmpty || cvvCtrl.text.trim().isNotEmpty || pinCtrl.text.trim().isNotEmpty) {
                        final cipher = ref.read(secretCipherServiceProvider);
                        if (!cipher.isReady) await cipher.restoreFromCache();
                        if (cipher.isReady) {
                          if (rawNum.isNotEmpty) {
                            encNum = cipher.encryptField(rawNum);
                            if (rawNum.length >= 4) newLast4 = rawNum.substring(rawNum.length - 4);
                          }
                          if (cvvCtrl.text.trim().isNotEmpty) encCvv = cipher.encryptField(cvvCtrl.text.trim());
                          if (pinCtrl.text.trim().isNotEmpty) encPin = cipher.encryptField(pinCtrl.text.trim());
                        } else {
                          setSheetState(() => error = 'Secure storage is locked — sign in again to edit encrypted details');
                          return;
                        }
                      }
                      try {
                        await ref.read(financeNotifierProvider.notifier).updateCard(
                          card.id,
                          name: nameCtrl.text.trim(),
                          bank: bankCtrl.text.trim(),
                          cardholderName: holderCtrl.text.trim(),
                          last4: newLast4,
                          colorHex: colorHex,
                          encCardNumber: encNum,
                          encCvv: encCvv,
                          encPin: encPin,
                          creditLimit: limit,
                          statementDay: statementDay,
                          dueDay: dueDay,
                          linkedAccountId: isDebit ? linkedAccountId : null,
                        );
                        navigator.pop();
                      } catch (e) {
                        setSheetState(() => error = 'Failed to save: $e');
                      }
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
        title: Text('Remove Card?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove ${card.name} (•••• ${card.last4}) from your vault?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.expense,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Captured as a local so the `mounted` narrowing below actually
              // applies — `context` is `State.context`, a getter, and the
              // analyzer can't promote across separate getter reads.
              final screenContext = context;
              Object? failure;
              try {
                await ref.read(financeNotifierProvider.notifier).deleteCard(card.id);
              } catch (e) {
                failure = e;
              }
              if (!screenContext.mounted) return;
              if (failure == null) {
                showUndoDeleteSnackBar(
                  screenContext,
                  message: '${card.name} removed',
                  onUndo: () => ref.read(financeNotifierProvider.notifier).undoDelete('credit_cards', card.id),
                );
              } else {
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  SnackBar(content: Text('Delete failed: $failure'), backgroundColor: AppColors.expense),
                );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveCardCarousel extends StatefulWidget {
  final List<CardModel> cards;
  final ValueChanged<int> onPageChanged;

  const _ResponsiveCardCarousel({
    required this.cards,
    required this.onPageChanged,
  });

  @override
  State<_ResponsiveCardCarousel> createState() => _ResponsiveCardCarouselState();
}

class _ResponsiveCardCarouselState extends State<_ResponsiveCardCarousel> {
  late PageController _pageController;
  late double _viewportFraction;
  late double _carouselHeight;

  @override
  void initState() {
    super.initState();
    // Safe defaults — the responsive metrics depend on MediaQuery, which is
    // not available until didChangeDependencies.
    _viewportFraction = 0.88;
    _carouselHeight = 210.0;
    _pageController = PageController(viewportFraction: _viewportFraction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyResponsiveMetrics();
  }

  @override
  void didUpdateWidget(covariant _ResponsiveCardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyResponsiveMetrics();
  }

  void _applyResponsiveMetrics() {
    final isTablet = context.isTablet;
    final newViewportFraction = isTablet ? 0.48 : 0.88;
    final newCarouselHeight = isTablet ? 200.0 : 210.0;
    if (newViewportFraction == _viewportFraction &&
        newCarouselHeight == _carouselHeight) {
      return;
    }
    _viewportFraction = newViewportFraction;
    _carouselHeight = newCarouselHeight;
    final previous = _pageController;
    _pageController = PageController(viewportFraction: _viewportFraction);
    previous.dispose();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    return SizedBox(
      height: _carouselHeight,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.cards.length,
        onPageChanged: widget.onPageChanged,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6),
          child: _GlassCard(card: widget.cards[i]),
        ),
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
    final colors = cardGradientColors(card);
    final fg = cardForeground(colors);
    final fgSoft = fg.withValues(alpha: 0.6);

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
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CARD HOLDER',
                            style: TextStyle(color: fgSoft, fontSize: 9, letterSpacing: 1),
                          ),
                          Text(
                            card.cardholderName.isEmpty ? card.bank : card.cardholderName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'EXPIRES',
                          style: TextStyle(color: fgSoft, fontSize: 9, letterSpacing: 1),
                        ),
                        Text(
                          card.expiryDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: card.isExpired ? Colors.red[300] : fg,
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
  final AccountModel? linkedAccount;
  final VoidCallback onPayBill;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewSecrets;
  const _CardListTile({required this.card, this.linkedAccount, required this.onPayBill, required this.onEdit, required this.onDelete, required this.onViewSecrets});

  bool get _hasSecrets => card.encCardNumber != null || card.encCvv != null || card.encPin != null;

  @override
  Widget build(BuildContext context) {
    final colors = cardGradientColors(card);
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(card.cardType.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (card.isExpired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.expense.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
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
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${card.bank}  •  ${card.network.displayName}  •  •••• ${card.last4}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: Icon(LucideIcons.moreVertical, color: AppColors.textMuted, size: 18),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                itemBuilder: (_) => [
                  if (isCredit)
                    PopupMenuItem(
                      value: 'pay',
                      child: Row(
                        children: [
                          Icon(LucideIcons.arrowRightLeft, size: 14, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Pay Bill', style: TextStyle(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  if (_hasSecrets)
                    PopupMenuItem(
                      value: 'secrets',
                      child: Row(
                        children: [
                          Icon(LucideIcons.lock, size: 14, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Card details', style: TextStyle(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(LucideIcons.pencil, size: 14, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
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
                  } else if (v == 'secrets') {
                    onViewSecrets();
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
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _InfoChip(
                    label: 'Outstanding',
                    value: CurrencyFormatter.format(card.currentOutstanding),
                    valueColor: AppColors.expense,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoChip(
                    label: 'Available',
                    value: CurrencyFormatter.format(card.availableLimit),
                    valueColor: AppColors.income,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoChip(
                    label: 'Limit',
                    value: CurrencyFormatter.format(card.creditLimit),
                    valueColor: AppColors.textPrimary,
                  ),
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
              children: [
                Expanded(
                  child: Text(
                    'Stmt: ${card.statementDay}th  •  Due: ${card.dueDay}th',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onPayBill,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Pay Bill',
                      style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (card.cardType == CardType.debit) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            if (linkedAccount != null) ...[
              Row(
                children: [
                  Icon(LucideIcons.building2, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Linked to ${linkedAccount!.name}'
                      '${(linkedAccount!.accountNumberLast4 != null && linkedAccount!.accountNumberLast4!.isNotEmpty) ? '  ••••${linkedAccount!.accountNumberLast4}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.wallet, size: 14, color: AppColors.income),
                  const SizedBox(width: 6),
                  Text('Balance: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  Expanded(
                    child: Text(
                      CurrencyFormatter.format(linkedAccount!.calculatedBalance),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.income),
                    ),
                  ),
                ],
              ),
            ] else
              GestureDetector(
                onTap: onEdit,
                child: Row(
                  children: [
                    Icon(LucideIcons.link, size: 13, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Link a bank account so purchases deduct correctly',
                        style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 14, color: AppColors.warning),
                  ],
                ),
              ),
          ],

          if ((card.cardType == CardType.prepaid || card.cardType == CardType.forex) && hasFunds) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.wallet, size: 14, color: AppColors.income),
                const SizedBox(width: 6),
                Text('Balance: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Expanded(
                  child: Text(
                    card.currency != null && card.currency != 'INR'
                        ? '${card.currency} ${card.balance!.toStringAsFixed(2)}'
                        : CurrencyFormatter.format(card.balance!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.income),
                  ),
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
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor)),
      ),
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
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: AppDecorations.iconBadge(color, circle: true),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ],
  );
}

// ─── Card Secrets Sheet ───────────────────────────────────────────────────────
class _CardSecretsSheet extends StatelessWidget {
  final CardModel card;
  const _CardSecretsSheet({required this.card});

  @override
  Widget build(BuildContext context) {
    return SecretRevealSheet(
      title: '${card.name} details',
      fields: [
        SecretField('Card number', card.encCardNumber,
            maskedFallback: '•••• •••• •••• ${card.last4}', groupDigits: true),
        SecretField('CVV', card.encCvv, maskedFallback: '•••'),
        SecretField('ATM PIN', card.encPin, maskedFallback: '••••'),
      ],
    );
  }
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
  String? _customColorHex;
  String? _linkedAccountId;
  String? _linkError;

  final _nameCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _last4Ctrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'USD');
  final _cardNumCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  int? _expiryMonth;
  int? _expiryYear;
  int _statementDay = 1;
  int _dueDay = 15;
  bool _isVirtual = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _bankCtrl, _last4Ctrl, _holderCtrl, _limitCtrl, _balanceCtrl, _notesCtrl, _currencyCtrl, _cardNumCtrl, _cvvCtrl, _pinCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkableAccounts = ref
        .watch(financeNotifierProvider)
        .accountsWithCalculatedBalances
        .where((a) => !a.isDeleted)
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
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
                  Text(
                    'Add New Card',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.border, height: 1),

            Expanded(
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 100),
                children: [
                  // Card type selector
                  Text('Card Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
                  const SizedBox(height: 16),

                  // ── Sensitive details (encrypted on-device) ──
                  Row(
                    children: [
                      Icon(LucideIcons.lock, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Sensitive details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Encrypted on this device. The full number sets the last 4 automatically.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  _field(
                    _cardNumCtrl,
                    'Card Number',
                    hint: '•••• •••• •••• ••••',
                    icon: LucideIcons.creditCard,
                    inputType: TextInputType.number,
                    formatter: FilteringTextInputFormatter.digitsOnly,
                    maxLen: 19,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          _cvvCtrl,
                          'CVV',
                          hint: '•••',
                          icon: LucideIcons.shield,
                          inputType: TextInputType.number,
                          formatter: FilteringTextInputFormatter.digitsOnly,
                          maxLen: 4,
                          obscure: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          _pinCtrl,
                          'ATM PIN',
                          hint: '••••',
                          icon: LucideIcons.keyRound,
                          inputType: TextInputType.number,
                          formatter: FilteringTextInputFormatter.digitsOnly,
                          maxLen: 6,
                          obscure: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Network
                  Text('Network', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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

                  // Debit-card ↔ bank-account linkage. A purchase on a debit
                  // card deducts from the linked account's balance — it does
                  // not accrue a separate "outstanding" the way credit does.
                  if (_selectedType == CardType.debit) ...[
                    _buildLinkedAccountPicker(linkableAccounts),
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
                        Icon(LucideIcons.wifi, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
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
                  Text('Card Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
    final custom = parseCardHex(_customColorHex);
    final colors = custom != null
        ? cardGradientColors(CardModel(
            id: '_', cardType: _selectedType, name: '', bank: '', last4: '',
            cardholderName: '', colorHex: _customColorHex))
        : _selectedColor.gradientColors.map((c) => Color(c)).toList();
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
            onTap: () => setState(() {
              _selectedType = type;
              _linkError = null;
            }),
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
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
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
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
    final customColor = parseCardHex(_customColorHex);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...CardColorPreset.values.map((preset) {
            final selected = _customColorHex == null && preset == _selectedColor;
            final colors = preset.gradientColors.map((c) => Color(c)).toList();
            return GestureDetector(
              onTap: () => setState(() {
                _selectedColor = preset;
                _customColorHex = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 3),
                  boxShadow: selected ? [BoxShadow(color: colors.last.withValues(alpha: 0.5), blurRadius: 8)] : null,
                ),
                child: selected ? const Icon(LucideIcons.check, color: Colors.white, size: 16) : null,
              ),
            );
          }),
          // Custom colour picker
          GestureDetector(
            onTap: _pickCustomColor,
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: customColor ?? AppColors.surfaceLight,
                gradient: customColor == null
                    ? const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFF10B981)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                shape: BoxShape.circle,
                border: Border.all(color: _customColorHex != null ? Colors.white : AppColors.border, width: 3),
              ),
              child: Icon(
                _customColorHex != null ? LucideIcons.check : LucideIcons.plus,
                color: customColor != null ? cardForeground([customColor]) : Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomColor() async {
    Color picked = parseCardHex(_customColorHex) ?? const Color(0xFF3B82F6);
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Pick a card colour', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hueWheel,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, picked), child: const Text('Use colour')),
        ],
      ),
    );
    if (result != null) {
      setState(() => _customColorHex = cardHexOf(result));
    }
  }

  Widget _buildLinkedAccountPicker(List<AccountModel> accounts) {
    final validId = accounts.any((a) => a.id == _linkedAccountId) ? _linkedAccountId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.building2, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Linked Bank Account',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Purchases on this card deduct from the linked account.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        if (accounts.isEmpty)
          Text('Add a bank account first — a debit card must be linked to one.',
              style: TextStyle(fontSize: 12, color: AppColors.expense))
        else
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: validId,
            dropdownColor: AppColors.surface,
            hint: Text('Select an account', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            ),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            items: accounts.map((a) {
              final l4 = (a.accountNumberLast4 != null && a.accountNumberLast4!.isNotEmpty)
                  ? '  ••••${a.accountNumberLast4}'
                  : '';
              return DropdownMenuItem(
                value: a.id,
                child: Text('${a.name} · ${a.type.displayName}$l4', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) => setState(() {
              _linkedAccountId = v;
              _linkError = null;
            }),
          ),
        if (_linkError != null) ...[
          const SizedBox(height: 6),
          Text(_linkError!, style: TextStyle(fontSize: 12, color: AppColors.expense)),
        ],
      ],
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
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(display(i), style: TextStyle(color: AppColors.textPrimary, fontSize: 13)))).toList(),
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.surface,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
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
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      maxLength: maxLen,
      maxLines: maxLines,
      obscureText: obscure,
      inputFormatters: formatter != null ? [formatter] : null,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 16, color: AppColors.textMuted) : null,
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        labelStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Future<void> _save() async {
    final rawNumber = _cardNumCtrl.text.replaceAll(RegExp(r'\D'), '');
    var last4 = _last4Ctrl.text.trim();
    if (rawNumber.length >= 12) last4 = rawNumber.substring(rawNumber.length - 4);

    if (_nameCtrl.text.trim().isEmpty || _bankCtrl.text.trim().isEmpty || last4.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill card name, bank, and the card number (or last 4 digits)'), backgroundColor: AppColors.expense),
      );
      return;
    }
    final limit = double.tryParse(_limitCtrl.text) ?? 0;
    if (limit < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Credit limit cannot be negative'), backgroundColor: AppColors.expense),
      );
      return;
    }
    final balance = double.tryParse(_balanceCtrl.text);
    if (balance != null && balance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Balance cannot be negative'), backgroundColor: AppColors.expense),
      );
      return;
    }
    if (_selectedType == CardType.debit) {
      final accounts = ref.read(financeNotifierProvider).accounts;
      final linked = _linkedAccountId != null &&
          accounts.any((a) => a.id == _linkedAccountId && !a.isDeleted);
      if (!linked) {
        setState(() => _linkError = 'Select the bank account this debit card draws from');
        return;
      }
    }
    setState(() => _saving = true);

    // Encrypt the sensitive fields transparently with the per-user DEK. Never
    // persist plaintext — if the cipher is not ready, skip capture and warn.
    String? encNumber, encCvv, encPin;
    final cvv = _cvvCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (rawNumber.isNotEmpty || cvv.isNotEmpty || pin.isNotEmpty) {
      final cipher = ref.read(secretCipherServiceProvider);
      if (!cipher.isReady) await cipher.restoreFromCache();
      if (cipher.isReady) {
        if (rawNumber.isNotEmpty) encNumber = cipher.encryptField(rawNumber);
        if (cvv.isNotEmpty) encCvv = cipher.encryptField(cvv);
        if (pin.isNotEmpty) encPin = cipher.encryptField(pin);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Secure storage is locked — card saved without the encrypted details'), backgroundColor: AppColors.warning),
        );
      }
    }
    if (!mounted) return;

    try {
      await ref.read(financeNotifierProvider.notifier).addCard(
        cardType: _selectedType,
        name: _nameCtrl.text.trim(),
        bank: _bankCtrl.text.trim(),
        last4: last4,
        cardholderName: _holderCtrl.text.trim(),
        network: _selectedNetwork,
        expiryMonth: _expiryMonth,
        expiryYear: _expiryYear,
        colorPreset: _selectedColor,
        colorHex: _customColorHex,
        isVirtual: _isVirtual,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        encCardNumber: encNumber,
        encCvv: encCvv,
        encPin: encPin,
        creditLimit: double.tryParse(_limitCtrl.text) ?? 0,
        statementDay: _statementDay,
        dueDay: _dueDay,
        linkedAccountId: _selectedType == CardType.debit ? _linkedAccountId : null,
        balance: double.tryParse(_balanceCtrl.text),
        currency: _selectedType == CardType.forex ? _currencyCtrl.text.trim().toUpperCase() : null,
      );

      if (!mounted) return;
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save card: $e'), backgroundColor: AppColors.expense),
      );
    }
  }
}
