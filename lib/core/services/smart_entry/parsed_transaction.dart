import '../../constants/app_constants.dart';

/// Where a [ParsedTransaction] came from — shown in the review inbox and used
/// to pick sensible defaults (e.g. an SMS debit is almost always an expense).
enum CaptureSource { typed, voice, receipt, sms, notification, shortcut, share }

extension CaptureSourceLabel on CaptureSource {
  String get label => switch (this) {
        CaptureSource.typed => 'Typed',
        CaptureSource.voice => 'Voice',
        CaptureSource.receipt => 'Receipt',
        CaptureSource.sms => 'SMS',
        CaptureSource.notification => 'Notification',
        CaptureSource.shortcut => 'Shortcut',
        CaptureSource.share => 'Shared',
      };
}

/// A best-effort transaction draft produced by any of the smart-entry parsers
/// (one-line text, voice, receipt OCR, bank SMS / app notification, AI).
///
/// Every field is optional — the Quick Add sheet pre-fills only what was
/// found and leaves the rest on its normal defaults. Ids ([accountId],
/// [payCardId], [categoryId]) are already resolved against the user's data;
/// [payCardId] may be the cash sentinel `kCashPaySentinel`.
class ParsedTransaction {
  final TransactionType? type;
  final double? amount;
  final String? merchant;
  final String? categoryId;
  final String? accountId;
  final String? payCardId;
  final DateTime? date;
  final String? notes;

  /// The text the draft was parsed from (SMS body, transcript, OCR text…).
  final String? rawText;

  /// Bank reference / UPI ref number, used to de-duplicate the same payment
  /// arriving as both an SMS and an app notification.
  final String? reference;

  /// Last 4 digits of the account/card the message mentions, if any.
  final String? last4;

  const ParsedTransaction({
    this.type,
    this.amount,
    this.merchant,
    this.categoryId,
    this.accountId,
    this.payCardId,
    this.date,
    this.notes,
    this.rawText,
    this.reference,
    this.last4,
  });

  bool get hasAmount => amount != null && amount! > 0;

  ParsedTransaction copyWith({
    TransactionType? type,
    double? amount,
    String? merchant,
    String? categoryId,
    String? accountId,
    String? payCardId,
    DateTime? date,
    String? notes,
    String? rawText,
    String? reference,
    String? last4,
  }) {
    return ParsedTransaction(
      type: type ?? this.type,
      amount: amount ?? this.amount,
      merchant: merchant ?? this.merchant,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      payCardId: payCardId ?? this.payCardId,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      rawText: rawText ?? this.rawText,
      reference: reference ?? this.reference,
      last4: last4 ?? this.last4,
    );
  }

  /// Fills any field this draft is missing from [other] (this one wins).
  ParsedTransaction mergeMissingFrom(ParsedTransaction other) {
    return ParsedTransaction(
      type: type ?? other.type,
      amount: amount ?? other.amount,
      merchant: merchant ?? other.merchant,
      categoryId: categoryId ?? other.categoryId,
      accountId: accountId ?? other.accountId,
      payCardId: payCardId ?? other.payCardId,
      date: date ?? other.date,
      notes: notes ?? other.notes,
      rawText: rawText ?? other.rawText,
      reference: reference ?? other.reference,
      last4: last4 ?? other.last4,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type?.name,
        'amount': amount,
        'merchant': merchant,
        'categoryId': categoryId,
        'accountId': accountId,
        'payCardId': payCardId,
        'date': date?.toIso8601String(),
        'notes': notes,
        'rawText': rawText,
        'reference': reference,
        'last4': last4,
      };

  factory ParsedTransaction.fromJson(Map<String, dynamic> j) {
    TransactionType? type;
    final t = j['type'] as String?;
    if (t != null) {
      for (final v in TransactionType.values) {
        if (v.name == t) type = v;
      }
    }
    return ParsedTransaction(
      type: type,
      amount: (j['amount'] as num?)?.toDouble(),
      merchant: j['merchant'] as String?,
      categoryId: j['categoryId'] as String?,
      accountId: j['accountId'] as String?,
      payCardId: j['payCardId'] as String?,
      date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
      notes: j['notes'] as String?,
      rawText: j['rawText'] as String?,
      reference: j['reference'] as String?,
      last4: j['last4'] as String?,
    );
  }

  @override
  String toString() => 'ParsedTransaction(${type?.name}, $amount, merchant: $merchant, '
      'cat: $categoryId, acc: $accountId, pay: $payCardId, date: $date)';
}
