import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart' show FinanceState;
import '../../../domain/models/models.dart';

/// The account / pay-with instrument a piece of text refers to.
class ResolvedInstrument {
  final String? accountId;

  /// A card id or [kCashPaySentinel]; null means "bank account (default)".
  final String? payCardId;

  /// The words in the text that matched (so the parser can strip them out of
  /// the merchant name).
  final List<String> matchedWords;

  const ResolvedInstrument({this.accountId, this.payCardId, this.matchedWords = const []});

  bool get isEmpty => accountId == null && payCardId == null;
}

/// Matches free text ("hdfc", "icici card", "xx4321", "cash", "sbi debit")
/// against the user's own accounts and cards.
class EntityResolver {
  final FinanceState state;
  EntityResolver(this.state);

  static const cashWords = {'cash', 'nagad'};
  static const _cardWords = {'card', 'cc', 'credit'};
  static const _debitWords = {'debit', 'dc'};

  static final _stop = {'bank', 'account', 'a/c', 'ac', 'the', 'my', 'of', 'ltd', 'limited', 'savings', 'saving'};

  static List<String> _tokens(String s) =>
      s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();

  Iterable<AccountModel> get _accounts => state.accounts.where((a) => !a.isDeleted);
  Iterable<CardModel> get _cards => state.creditCards.where(
        (c) => !c.isDeleted && (c.cardType == CardType.credit || c.cardType == CardType.debit),
      );

  /// Resolves by the last 4 digits a bank message quotes ("A/c XX1234",
  /// "Card ending 1234"). Cards win over accounts when both match.
  ResolvedInstrument byLast4(String last4, {bool preferCard = false}) {
    final cards = _cards.where((c) => c.last4 == last4).toList();
    final accs = _accounts.where((a) => a.accountNumberLast4 == last4).toList();
    if (cards.isNotEmpty && (preferCard || accs.isEmpty)) return _forCard(cards.first, [last4]);
    if (accs.isNotEmpty) return ResolvedInstrument(accountId: accs.first.id, matchedWords: [last4]);
    if (cards.isNotEmpty) return _forCard(cards.first, [last4]);
    return const ResolvedInstrument();
  }

  ResolvedInstrument _forCard(CardModel c, List<String> words) {
    if (c.cardType == CardType.debit) {
      return ResolvedInstrument(accountId: c.linkedAccountId, payCardId: c.id, matchedWords: words);
    }
    return ResolvedInstrument(payCardId: c.id, matchedWords: words);
  }

  /// Finds the instrument named in a free-text entry. Returns an empty result
  /// when nothing matches — the caller keeps its own default.
  ResolvedInstrument fromText(String text) {
    final words = _tokens(text);
    if (words.any(cashWords.contains)) {
      return ResolvedInstrument(payCardId: kCashPaySentinel, matchedWords: words.where(cashWords.contains).toList());
    }

    // Only explicit "xx1234" / "*1234" / "ending 1234" forms — a bare 4-digit
    // number in typed text is far more likely to be the amount.
    final digits = RegExp(r'(?:x+|\*+|ending\s*|last\s*)(\d{4})\b', caseSensitive: false)
        .allMatches(text.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();
    for (final d in digits) {
      final r = byLast4(d);
      if (!r.isEmpty) return r;
    }

    final wantsCard = words.any(_cardWords.contains);
    final wantsDebit = words.any(_debitWords.contains);

    Set<String> clean(Iterable<String> ws) => ws.where((w) => !_stop.contains(w) && w.length >= 2).toSet();
    int hits(Set<String> set) => words.where(set.contains).length;

    // Bank words ("hdfc", "icici") are strong evidence; words that only appear
    // in a product name ("amazon" in "ICICI Amazon Pay") are weak, because
    // they are usually the merchant — they only count when the text also
    // says "card".
    CardModel? bestCard;
    var bestCardScore = 0;
    for (final c in _cards) {
      final bankSet = clean(_tokens(c.bank));
      final nameOnly = clean(_tokens(c.name)).difference(bankSet);
      final bankHits = hits(bankSet);
      final nameHits = hits(nameOnly);
      if (bankHits == 0 && !(nameHits > 0 && (wantsCard || wantsDebit))) continue;
      final typeBonus = (wantsDebit && c.cardType == CardType.debit) || (wantsCard && !wantsDebit && c.cardType == CardType.credit) ? 1 : 0;
      final s = bankHits * 2 + nameHits + typeBonus;
      if (s > bestCardScore) {
        bestCard = c;
        bestCardScore = s;
      }
    }

    AccountModel? bestAcc;
    var bestAccScore = 0;
    for (final a in _accounts) {
      final bankSet = clean(_tokens(a.bank ?? ''));
      final nameOnly = clean(_tokens(a.name)).difference(bankSet);
      final s = hits(bankSet) * 2 + hits(nameOnly) * 2;
      if (s > bestAccScore) {
        bestAcc = a;
        bestAccScore = s;
      }
    }

    // Only bank words + "card/debit" are stripped from the text; name-only
    // words stay so they can still be the merchant ("Amazon", "Salary").
    List<String> matched(String bank, String name) {
      final bankSet = clean(_tokens(bank));
      final set = bankSet.isNotEmpty ? bankSet : clean(_tokens(name));
      return [...words.where(set.contains), ...words.where((w) => _cardWords.contains(w) || _debitWords.contains(w))];
    }

    // "hdfc card" → the card; plain "hdfc" → the account (cards only win when
    // the text says card/credit/debit, or no account matches at all).
    if (bestCard != null && (wantsCard || wantsDebit || bestAcc == null || bestCardScore > bestAccScore)) {
      return _forCard(bestCard, matched(bestCard.bank, bestCard.name));
    }
    if (bestAcc != null) {
      return ResolvedInstrument(accountId: bestAcc.id, matchedWords: matched(bestAcc.bank ?? '', bestAcc.name));
    }
    return const ResolvedInstrument();
  }
}
