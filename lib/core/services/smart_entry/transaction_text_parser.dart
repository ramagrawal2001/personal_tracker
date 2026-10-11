import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart' show FinanceState;
import 'entity_resolver.dart';
import 'entry_suggestions.dart';
import 'parsed_transaction.dart';

/// Offline parser for one-line / spoken entries such as
///   "450 zomato hdfc card yesterday"
///   "spent 2.5k on groceries cash"
///   "received 50000 salary"
///   "two hundred for petrol on monday"
///
/// Always available (no network, no API key). The AI parser falls back to
/// this, and its result is merged on top of this one.
class TransactionTextParser {
  final FinanceState state;
  final DateTime Function() _now;

  TransactionTextParser(this.state, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  static const _incomeWords = {
    'received', 'receive', 'got', 'salary', 'credited', 'credit', 'income', 'earned', 'refund', 'refunded', 'cashback', 'bonus',
  };
  static const _expenseWords = {'spent', 'spend', 'paid', 'pay', 'bought', 'buy', 'debited', 'expense'};

  static const _filler = {
    'spent', 'spend', 'paid', 'pay', 'bought', 'buy', 'debited', 'expense', 'received', 'receive', 'got', 'credited',
    'income', 'earned', 'rs', 'inr', 'rupees', 'rupee', 'bucks', 'on', 'at', 'to', 'from', 'via', 'using', 'with', 'by',
    'through', 'a', 'an', 'the', 'my', 'of', 'in', 'upi', 'gpay', 'phonepe', 'for', 'and', 'i', 'me', 'card', 'account',
    'ago', 'days', 'day', 'today', 'yesterday', 'last', 'this', 'just', 'some', 'rs.', 'worth',
  };

  static const _weekdays = {
    'monday': DateTime.monday, 'mon': DateTime.monday,
    'tuesday': DateTime.tuesday, 'tue': DateTime.tuesday, 'tues': DateTime.tuesday,
    'wednesday': DateTime.wednesday, 'wed': DateTime.wednesday,
    'thursday': DateTime.thursday, 'thu': DateTime.thursday, 'thurs': DateTime.thursday,
    'friday': DateTime.friday, 'fri': DateTime.friday,
    'saturday': DateTime.saturday, 'sat': DateTime.saturday,
    'sunday': DateTime.sunday, 'sun': DateTime.sunday,
  };

  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4, 'may': 5,
    'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  };

  static const _numberWords = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };
  static const _scaleWords = {'hundred': 100, 'thousand': 1000, 'k': 1000, 'lakh': 100000, 'lakhs': 100000, 'lac': 100000};

  ParsedTransaction parse(String input, {CaptureSource source = CaptureSource.typed}) {
    var text = ' ${input.trim()} ';
    if (text.trim().isEmpty) return ParsedTransaction(rawText: input);
    final lower = text.toLowerCase();
    final now = _now();

    // ── Date ────────────────────────────────────────────────────────────
    DateTime? date;
    String dateLess = lower;
    void takeDate(RegExp re, DateTime? Function(Match m) build) {
      if (date != null) return;
      final m = re.firstMatch(dateLess);
      if (m == null) return;
      final d = build(m);
      if (d == null) return;
      date = d;
      dateLess = dateLess.replaceRange(m.start, m.end, ' ');
    }

    final today = DateTime(now.year, now.month, now.day);
    takeDate(RegExp(r'\bday before yesterday\b'), (_) => today.subtract(const Duration(days: 2)));
    takeDate(RegExp(r'\byesterday\b'), (_) => today.subtract(const Duration(days: 1)));
    takeDate(RegExp(r'\btoday\b|\btonight\b|\bthis morning\b'), (_) => today);
    takeDate(RegExp(r'\b(\d{1,2})\s+days?\s+ago\b'), (m) => today.subtract(Duration(days: int.parse(m.group(1)!))));
    takeDate(
      RegExp(r'\b(?:on\s+|last\s+)?(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thu|friday|fri|saturday|sat|sunday|sun)\b'),
      (m) {
        final wd = _weekdays[m.group(1)!]!;
        var diff = (today.weekday - wd) % 7;
        if (diff == 0 && m.group(0)!.contains('last')) diff = 7;
        return today.subtract(Duration(days: diff));
      },
    );
    takeDate(
      RegExp(r'\b(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b'),
      (m) => _pastDate(now, _months[m.group(2)!]!, int.parse(m.group(1)!)),
    );
    takeDate(
      RegExp(r'\b(?:on\s+)?(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+(\d{1,2})(?:st|nd|rd|th)?\b'),
      (m) => _pastDate(now, _months[m.group(1)!]!, int.parse(m.group(2)!)),
    );
    takeDate(RegExp(r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b'), (m) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
      if (m.group(3) != null) {
        var y = int.parse(m.group(3)!);
        if (y < 100) y += 2000;
        return DateTime(y, mo, d);
      }
      return _pastDate(now, mo, d);
    });
    takeDate(RegExp(r'\bon\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b'), (m) {
      final d = int.parse(m.group(1)!);
      if (d < 1 || d > 31) return null;
      var c = DateTime(now.year, now.month, d);
      if (c.isAfter(today)) c = DateTime(now.year, now.month - 1, d);
      return c;
    });

    // ── Amount ──────────────────────────────────────────────────────────
    double? amount;
    String rest = dateLess;
    final numRe = RegExp(r'(?:₹|rs\.?|inr)?\s*(\d[\d,]*(?:\.\d+)?)\s*(k|lakhs?|lac)?\b');
    final numMatch = numRe.firstMatch(rest);
    if (numMatch != null) {
      amount = double.tryParse(numMatch.group(1)!.replaceAll(',', ''));
      final suffix = numMatch.group(2);
      if (amount != null && suffix != null) amount *= suffix == 'k' ? 1000 : 100000;
      rest = rest.replaceRange(numMatch.start, numMatch.end, ' ');
    } else {
      final w = _wordsToNumber(rest);
      if (w != null) {
        amount = w.$1;
        rest = rest.replaceAll(w.$2, ' ');
      }
    }

    // ── Type ────────────────────────────────────────────────────────────
    final words = rest.split(RegExp(r'[^a-z0-9&\x27.]+')).where((w) => w.isNotEmpty).toList();
    TransactionType? type;
    if (words.any(_incomeWords.contains) && !words.any(_expenseWords.contains)) {
      type = TransactionType.income;
    } else if (amount != null || words.any(_expenseWords.contains)) {
      type = TransactionType.expense;
    }

    // ── Account / pay-with ──────────────────────────────────────────────
    final resolver = EntityResolver(state);
    final inst = resolver.fromText(rest);
    final instWords = inst.matchedWords.toSet();

    // ── Merchant & notes ────────────────────────────────────────────────
    // "500 to ramesh for dinner" → merchant "ramesh", notes "dinner".
    String? notes;
    var merchantPart = rest;
    final forIdx = RegExp(r'\bfor\b').firstMatch(rest);
    if (forIdx != null) {
      final before = _clean(rest.substring(0, forIdx.start), instWords);
      final after = _clean(rest.substring(forIdx.end), instWords);
      if (before.isNotEmpty && after.isNotEmpty) {
        merchantPart = before;
        notes = after;
      }
    }
    final merchantRaw = _clean(merchantPart, instWords);
    final merchant = merchantRaw.isEmpty ? null : _titleCase(merchantRaw);

    final suggestions = EntrySuggestions(state);
    final effectiveType = type ?? TransactionType.expense;
    String? categoryId;
    final mem = merchant == null ? null : suggestions.forMerchant(merchant);
    if (notes != null) categoryId = suggestions.categoryFor(notes, type: effectiveType);
    categoryId ??= merchant == null ? null : suggestions.categoryFor(merchant, type: effectiveType);

    // Instrument: what the text says, else the merchant's usual one.
    var accountId = inst.accountId;
    var payCardId = inst.payCardId;
    if (inst.isEmpty && mem != null) {
      accountId = mem.accountId;
      payCardId = mem.payCardId;
    }
    if (effectiveType != TransactionType.expense) payCardId = null;

    return ParsedTransaction(
      type: type,
      amount: amount,
      merchant: merchant,
      categoryId: categoryId,
      accountId: accountId,
      payCardId: payCardId,
      date: date,
      notes: notes == null ? null : _capitalize(notes),
      rawText: input.trim(),
    );
  }

  static DateTime _pastDate(DateTime now, int month, int day) {
    var c = DateTime(now.year, month, day);
    if (c.isAfter(now)) c = DateTime(now.year - 1, month, day);
    return c;
  }

  String _clean(String s, Set<String> instWords) {
    final words = s
        .split(RegExp(r'[^a-zA-Z0-9&\x27.]+'))
        .map((w) => w.replaceAll(RegExp(r'^\.+|\.+$'), ''))
        .where((w) => w.isNotEmpty)
        .where((w) => !_filler.contains(w.toLowerCase()))
        .where((w) => !instWords.contains(w.toLowerCase()))
        .where((w) => !_numberWords.containsKey(w.toLowerCase()) && !_scaleWords.containsKey(w.toLowerCase()))
        .where((w) => !EntityResolver.cashWords.contains(w.toLowerCase()))
        .toList();
    return words.join(' ');
  }

  static String _titleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : (w.length <= 3 && w == w.toUpperCase() ? w : w[0].toUpperCase() + w.substring(1)))
      .join(' ');

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// "two hundred fifty" → 250, "one thousand five hundred" → 1500.
  /// Returns the value and the matched phrase, or null.
  static (double, String)? _wordsToNumber(String text) {
    final re = RegExp(
      r'\b((?:(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|lakhs?|lac|and)\s*)+)\b',
    );
    for (final m in re.allMatches(text)) {
      final phrase = m.group(1)!.trim();
      final parts = phrase.split(RegExp(r'\s+')).where((w) => w != 'and').toList();
      if (parts.isEmpty) continue;
      var total = 0;
      var current = 0;
      var any = false;
      for (final p in parts) {
        if (_numberWords.containsKey(p)) {
          current += _numberWords[p]!;
          any = true;
        } else if (p == 'hundred') {
          current = (current == 0 ? 1 : current) * 100;
          any = true;
        } else if (_scaleWords.containsKey(p)) {
          total += (current == 0 ? 1 : current) * _scaleWords[p]!;
          current = 0;
          any = true;
        }
      }
      if (any) {
        final v = total + current;
        if (v > 0) return (v.toDouble(), phrase);
      }
    }
    return null;
  }
}
