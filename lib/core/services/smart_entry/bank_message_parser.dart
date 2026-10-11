import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart' show FinanceState;
import 'entity_resolver.dart';
import 'entry_suggestions.dart';
import 'parsed_transaction.dart';

/// Parses Indian bank / card / UPI alerts — SMS bodies and payment-app
/// notifications (GPay, PhonePe, Paytm, bank apps) — into a draft.
///
/// Returns null for anything that isn't a completed money movement (OTPs,
/// promos, "payment due" reminders, failed / declined transactions, balance
/// enquiries…), so the review inbox only ever shows real transactions.
class BankMessageParser {
  final FinanceState state;
  BankMessageParser(this.state);

  static final _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)|([\d,]+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|₹)',
    caseSensitive: false,
  );

  static final _debitRe = RegExp(
    r'\b(debited|spent|paid|sent|withdrawn|purchase|txn of|transaction of|charged|dr\b|debit)',
    caseSensitive: false,
  );
  static final _creditRe = RegExp(
    r'\b(credited|received|deposited|refund(?:ed)?|cr\b|added to)',
    caseSensitive: false,
  );

  // Messages that mention money but aren't a completed transaction.
  static final _rejectRe = RegExp(
    r'\b(otp|one time password|verification code|failed|declined|unsuccessful|reversed|due (?:on|date|by)|'
    r'is due|minimum (?:amount )?due|bill (?:is )?generated|statement (?:is )?generated|will be debited|'
    r'request(?:ed)? (?:money|rs|inr|₹)|has requested|collect request|pre-?approved|offer|cashback upto|'
    r'win |congratulations|loan of|eligible|apply now|avl bal of|available balance is)\b',
    caseSensitive: false,
  );

  static final _last4Re = RegExp(
    r'(?:a/?c|acct|account|card|ac)\s*(?:no\.?\s*)?(?:ending\s*(?:with\s*)?|xx+|\*+|x+|\.\.)?\s*[x*]*(\d{4})\b',
    caseSensitive: false,
  );
  static final _cardMentionRe = RegExp(r'\b(credit card|debit card|card)\b', caseSensitive: false);
  static final _creditCardRe = RegExp(r'\bcredit card\b', caseSensitive: false);

  static final _refRe = RegExp(
    r'(?:upi\s*ref(?:\.|erence)?\s*(?:no\.?)?|ref(?:\.|erence)?\s*(?:no\.?|number|#)?|txn\s*(?:id|no\.?)|utr)\s*[:\-]?\s*([a-z0-9]{6,})',
    caseSensitive: false,
  );

  // Merchant / counterparty patterns, tried in order.
  static final List<RegExp> _merchantRes = [
    RegExp(r'\bto\s+VPA\s+([\w.\-]+@[\w.\-]+)', caseSensitive: false),
    RegExp(r'\b(?:paid|sent)\s+(?:rs\.?|inr|₹)?\s*[\d,.]*\s*to\s+(.+?)(?=\s+(?:on|via|from|using|ref|upi|txn|with)\b|[.\n]|$)', caseSensitive: false),
    RegExp(r'\bat\s+(.+?)(?=\s+(?:on|via|from|using|ref|upi|txn|with|for|card|avl|avbl|bal)\b|[.\n]|$)', caseSensitive: false),
    RegExp(r'\binfo[:\-\s]+(?:upi/)?(?:p2[am]/)?(?:\d+/)?([^/\n.]+)', caseSensitive: false),
    RegExp(r';\s*([^;]+?)\s+credited\b', caseSensitive: false),
    RegExp(r'\btrf to\s+(.+?)(?=\s+(?:ref|on)\b|[.\n]|$)', caseSensitive: false),
    RegExp(r'\bto\s+([A-Za-z][\w &.\-]{1,40}?)(?=\s+(?:on|via|ref|upi|txn|from)\b|[.\n]|$)', caseSensitive: false),
    RegExp(r'\bfrom\s+([A-Za-z][\w &.\-]{1,40}?)(?=\s+(?:on|via|ref|upi|txn|to)\b|[.\n]|$)', caseSensitive: false),
    RegExp(r'\bby\s+([A-Za-z][\w &.\-]{1,40}?)(?=\s+(?:on|via|ref|upi|txn)\b|[.\n]|$)', caseSensitive: false),
  ];

  static final _dateRes = <RegExp>[
    RegExp(r'\b(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\b'),
    RegExp(r'\b(\d{1,2})[-\s]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-\s,]?(\d{2,4})?\b', caseSensitive: false),
  ];
  static const _mon = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

  /// Cheap pre-filter, mirrored by the native Android receivers so that only
  /// money messages are ever queued.
  static bool looksTransactional(String text) =>
      _amountRe.hasMatch(text) && (_debitRe.hasMatch(text) || _creditRe.hasMatch(text));

  ParsedTransaction? parse(String text, {DateTime? receivedAt, String? sender}) {
    final body = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty || _rejectRe.hasMatch(body)) return null;

    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;
    final amount = double.tryParse((amountMatch.group(1) ?? amountMatch.group(2))!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    final debit = _debitRe.firstMatch(body);
    final credit = _creditRe.firstMatch(body);
    if (debit == null && credit == null) return null;
    // Whichever verb appears first wins ("debited … credited to X's a/c" is a debit).
    final isIncome = credit != null && (debit == null || credit.start < debit.start);
    final type = isIncome ? TransactionType.income : TransactionType.expense;

    final last4 = _last4Re.firstMatch(body)?.group(1);
    final reference = _refRe.firstMatch(body)?.group(1);
    final merchant = _merchant(body, isIncome);
    final date = _date(body) ?? receivedAt;

    // Resolve account / card from the last-4 digits; a "credit card" alert
    // prefers a card over a same-digits account.
    final resolver = EntityResolver(state);
    var inst = const ResolvedInstrument();
    if (last4 != null) {
      inst = resolver.byLast4(last4, preferCard: _cardMentionRe.hasMatch(body));
    }
    if (inst.isEmpty && sender != null) {
      inst = resolver.fromText(sender.replaceAll(RegExp(r'^[A-Z]{2}-'), ''));
      // A sender id only identifies the bank, not a specific card.
      if (inst.payCardId != null && !_creditCardRe.hasMatch(body)) inst = ResolvedInstrument(accountId: inst.accountId);
    }

    final suggestions = EntrySuggestions(state);
    final mem = merchant == null ? null : suggestions.forMerchant(merchant);
    final categoryId = merchant == null ? null : suggestions.categoryFor(merchant, type: type);

    return ParsedTransaction(
      type: type,
      amount: amount,
      merchant: merchant,
      categoryId: categoryId,
      accountId: inst.accountId ?? mem?.accountId,
      payCardId: type == TransactionType.expense ? inst.payCardId : null,
      date: date,
      rawText: text.trim(),
      reference: reference,
      last4: last4,
    );
  }

  String? _merchant(String body, bool isIncome) {
    for (final re in _merchantRes) {
      final m = re.firstMatch(body);
      if (m == null) continue;
      var name = m.group(1)!.trim();
      name = name.replaceAll(RegExp(r'\s+(?:on|via)\s*$', caseSensitive: false), '');
      // VPA → the readable part before the handle ("swiggy.upi@axis" → Swiggy).
      if (name.contains('@')) {
        name = name.split('@').first.replaceAll(RegExp(r'[._\-]?(upi|pay|payments?|razorpay|rzp|\d+)$', caseSensitive: false), '');
        name = name.replaceAll(RegExp(r'[._\-]+'), ' ');
      }
      name = name.replaceAll(RegExp(r'\b(a/?c|acct|account)\b.*$', caseSensitive: false), '').trim();
      name = name.replaceAll(RegExp(r'[^\w &.\x27\-]'), '').trim();
      if (name.isEmpty || RegExp(r'^[\dx*]+$', caseSensitive: false).hasMatch(name)) continue;
      if (RegExp(r'^(your|you|the|a|an|self|xx+)$', caseSensitive: false).hasMatch(name)) continue;
      if (name.length > 40) name = name.substring(0, 40).trim();
      return _titleCase(name);
    }
    return null;
  }

  DateTime? _date(String body) {
    for (final re in _dateRes) {
      final m = re.firstMatch(body);
      if (m == null) continue;
      try {
        final d = int.parse(m.group(1)!);
        final month = int.tryParse(m.group(2)!) ?? _mon[m.group(2)!.toLowerCase().substring(0, 3)];
        if (month == null || month < 1 || month > 12 || d < 1 || d > 31) continue;
        var y = m.group(3) == null ? DateTime.now().year : int.parse(m.group(3)!);
        if (y < 100) y += 2000;
        final dt = DateTime(y, month, d);
        // Sanity: never in the future, never more than a year old.
        final now = DateTime.now();
        if (dt.isAfter(now.add(const Duration(days: 1))) || dt.isBefore(now.subtract(const Duration(days: 400)))) continue;
        return dt;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static const _acronyms = {'KFC', 'IRCTC', 'SBI', 'HDFC', 'ICICI', 'HP', 'BPCL', 'HPCL', 'IOCL', 'UPI', 'LIC', 'BSNL', 'ATM', 'NEFT', 'IMPS', 'DMART'};

  static String _titleCase(String s) {
    return s.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      final up = w.toUpperCase();
      if (_acronyms.contains(up)) return up == 'DMART' ? 'DMart' : up;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }
}
