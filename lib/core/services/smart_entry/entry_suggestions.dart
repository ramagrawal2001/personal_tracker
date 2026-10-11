import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart' show FinanceState;
import '../../../domain/models/models.dart';
import '../merchant_categorizer.dart';

/// What we remember about how the user usually logs a given merchant.
class MerchantMemory {
  final String merchant;
  final String? categoryId;
  final String? accountId;

  /// A card id, [kCashPaySentinel], or null for "bank account (default)".
  final String? payCardId;
  final TransactionType type;
  final int count;
  final double lastAmount;

  const MerchantMemory({
    required this.merchant,
    required this.type,
    this.categoryId,
    this.accountId,
    this.payCardId,
    this.count = 1,
    this.lastAmount = 0,
  });
}

/// Smart defaults derived purely from transaction history — nothing extra is
/// stored, so it "learns" automatically every time the user saves or corrects
/// a transaction, and stays in sync across devices with the data itself.
class EntrySuggestions {
  final FinanceState state;
  late final Map<String, MerchantMemory> _byMerchant = _buildMemory();

  EntrySuggestions(this.state);

  static String _key(String s) => s.trim().toLowerCase();

  Iterable<TransactionModel> get _history => state.transactions.where(
        (t) => !t.isDeleted && !t.isSettlement && !t.isExternalToAccount,
      );

  static String? payCardOf(TransactionModel t) {
    if (t.type != TransactionType.expense) return null;
    if (t.isCashSpend) return kCashPaySentinel;
    return t.creditCardId;
  }

  Map<String, MerchantMemory> _buildMemory() {
    // Newest first so the first hit per merchant is the most recent habit.
    final sorted = _history.where((t) => (t.merchant ?? '').trim().isNotEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.createdAt.compareTo(a.createdAt));
    final out = <String, MerchantMemory>{};
    final counts = <String, int>{};
    for (final t in sorted) {
      final k = _key(t.merchant!);
      counts[k] = (counts[k] ?? 0) + 1;
      out.putIfAbsent(
        k,
        () => MerchantMemory(
          merchant: t.merchant!.trim(),
          type: t.type,
          categoryId: t.categoryId,
          accountId: t.accountId,
          payCardId: payCardOf(t),
          lastAmount: t.amount,
        ),
      );
    }
    return {
      for (final e in out.entries)
        e.key: MerchantMemory(
          merchant: e.value.merchant,
          type: e.value.type,
          categoryId: e.value.categoryId,
          accountId: e.value.accountId,
          payCardId: e.value.payCardId,
          lastAmount: e.value.lastAmount,
          count: counts[e.key] ?? 1,
        ),
    };
  }

  /// Exact (case-insensitive) memory for [merchant], if it was used before.
  MerchantMemory? forMerchant(String merchant) => _byMerchant[_key(merchant)];

  /// Distinct merchants, most-used first — feeds the merchant autocomplete.
  List<String> merchants({TransactionType? type}) {
    final list = _byMerchant.values.where((m) => type == null || m.type == type).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.map((m) => m.merchant).toList();
  }

  /// Merchant names that start with / contain [query], best matches first.
  List<String> matchMerchants(String query, {TransactionType? type, int limit = 6}) {
    final q = _key(query);
    if (q.isEmpty) return const [];
    final all = merchants(type: type);
    final starts = all.where((m) => _key(m).startsWith(q));
    final contains = all.where((m) => !_key(m).startsWith(q) && _key(m).contains(q));
    return [...starts, ...contains].take(limit).toList();
  }

  /// Most recent transaction of [type] — its account / pay-with / category
  /// become the starting defaults for a fresh entry of that type.
  TransactionModel? lastOfType(TransactionType type) {
    TransactionModel? best;
    for (final t in _history) {
      if (t.type != type) continue;
      if (best == null || t.createdAt.isAfter(best.createdAt)) best = t;
    }
    return best;
  }

  /// Merchant+amount combos the user logs repeatedly (≥2 times), as quick
  /// one-tap chips. Ordered by frequency, then recency.
  List<MerchantMemory> frequentCombos({int limit = 6}) {
    final groups = <String, List<TransactionModel>>{};
    for (final t in _history) {
      final m = (t.merchant ?? '').trim();
      if (m.isEmpty) continue;
      if (t.type != TransactionType.expense && t.type != TransactionType.income) continue;
      groups.putIfAbsent('${_key(m)}|${t.amount.toStringAsFixed(2)}|${t.type.name}', () => []).add(t);
    }
    final combos = groups.values.where((g) => g.length >= 2).toList()
      ..sort((a, b) {
        final c = b.length.compareTo(a.length);
        if (c != 0) return c;
        final la = a.map((t) => t.date).reduce((x, y) => x.isAfter(y) ? x : y);
        final lb = b.map((t) => t.date).reduce((x, y) => x.isAfter(y) ? x : y);
        return lb.compareTo(la);
      });
    return combos.take(limit).map((g) {
      final latest = g.reduce((x, y) => x.date.isAfter(y.date) ? x : y);
      return MerchantMemory(
        merchant: latest.merchant!.trim(),
        type: latest.type,
        categoryId: latest.categoryId,
        accountId: latest.accountId,
        payCardId: payCardOf(latest),
        lastAmount: latest.amount,
        count: g.length,
      );
    }).toList();
  }

  /// Best category guess for a merchant / free text: the user's own history
  /// first, then the built-in merchant rules, then a category-name match.
  String? categoryFor(String text, {TransactionType type = TransactionType.expense}) {
    final mem = forMerchant(text);
    if (mem?.categoryId != null && _categoryValid(mem!.categoryId!, type)) return mem.categoryId;

    final rule = MerchantCategorizer.categorize(text);
    if (rule != null && _categoryValid(rule.categoryId, type)) return rule.categoryId;

    final lower = text.toLowerCase();
    final wantType = type == TransactionType.income ? 'income' : 'expense';
    for (final c in state.categories) {
      if (c.isDeleted || c.type != wantType) continue;
      final words = c.name.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3);
      if (words.any((w) => RegExp('\\b${RegExp.escape(w)}').hasMatch(lower))) return c.id;
    }
    return null;
  }

  bool _categoryValid(String id, TransactionType type) {
    final wantType = type == TransactionType.income ? 'income' : 'expense';
    return state.categories.any((c) => c.id == id && !c.isDeleted && c.type == wantType);
  }
}
