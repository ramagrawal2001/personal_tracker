import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart' show FinanceState;
import 'bank_message_parser.dart';
import 'entry_suggestions.dart';
import 'parsed_transaction.dart';

/// Turns on-device OCR text from a bill / receipt photo or a UPI "payment
/// successful" screenshot into a draft. Heuristic and offline; when an AI
/// provider is configured its result is layered on top.
class ReceiptParser {
  final FinanceState state;
  ReceiptParser(this.state);

  static final _money = RegExp(r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)', caseSensitive: false);
  static final _currencyMoney = RegExp(r'(?:₹|rs\.?|inr)\s*(\d[\d,]*(?:\.\d{1,2})?)', caseSensitive: false);
  static final _totalLine = RegExp(
    r'\b(grand\s*total|net\s*(?:amount|payable|total)|total\s*(?:amount|payable|due|paid)?|amount\s*(?:paid|payable)|bill\s*amount|to\s*pay)\b',
    caseSensitive: false,
  );
  static final _skipLine = RegExp(r'\b(sub\s*total|gst|cgst|sgst|igst|tax|discount|saved|savings|change|tendered|round)\b', caseSensitive: false);
  static final _upiPaidTo = RegExp(r'^(?:paid to|payment to|sent to|to)[:\s]+(.+)$', caseSensitive: false);
  static final _upiHeader = RegExp(r'\b(paid to|payment successful|transaction successful|sent to|money sent)\b', caseSensitive: false);

  ParsedTransaction parse(String ocrText) {
    final text = ocrText.trim();
    if (text.isEmpty) return const ParsedTransaction();

    // A screenshot of a bank SMS / UPI notification parses best as a message.
    final asMessage = BankMessageParser(state).parse(text);

    final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final isUpiScreen = _upiHeader.hasMatch(text);

    double? amount;
    String? merchant;

    if (isUpiScreen) {
      // UPI apps show the amount on its own line ("₹450" / "450.00").
      for (final l in lines) {
        final m = RegExp(r'^(?:₹|rs\.?|inr)?\s*(\d[\d,]*(?:\.\d{1,2})?)$', caseSensitive: false).firstMatch(l);
        if (m != null) {
          final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
          if (v != null && v > 0) {
            amount = v;
            break;
          }
        }
      }
      for (var i = 0; i < lines.length; i++) {
        final m = _upiPaidTo.firstMatch(lines[i]);
        if (m != null && m.group(1)!.trim().isNotEmpty) {
          merchant = m.group(1)!.trim();
          break;
        }
        if (RegExp(r'^(paid to|sent to|to)$', caseSensitive: false).hasMatch(lines[i]) && i + 1 < lines.length) {
          merchant = lines[i + 1];
          break;
        }
      }
    }

    if (amount == null) {
      // Bills: the largest amount on a "Total"-ish line, ignoring tax lines.
      double? best;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!_totalLine.hasMatch(l) || _skipLine.hasMatch(l)) continue;
        // Amount may be on the same line or the next one (two-column layouts).
        final candidates = [l, if (i + 1 < lines.length) lines[i + 1]];
        for (final c in candidates) {
          for (final m in _money.allMatches(c)) {
            final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
            if (v != null && v > 0 && v < 10000000 && (best == null || v > best)) best = v;
          }
          if (best != null) break;
        }
      }
      amount = best;
    }
    if (amount == null) {
      // Two-column bills OCR as "all labels, then all numbers", so the total
      // label and its value end up far apart. The grand total is the
      // largest money-shaped (x.xx) value that isn't on a tax/change line.
      double? best;
      for (final l in lines) {
        if (_skipLine.hasMatch(l)) continue;
        for (final m in RegExp(r'(?<![\d.])(\d{1,3}(?:,\d{2,3})+|\d+)\.(\d{2})(?![\d])').allMatches(l)) {
          final v = double.tryParse('${m.group(1)!.replaceAll(',', '')}.${m.group(2)}');
          if (v != null && v > 0 && v < 10000000 && (best == null || v > best)) best = v;
        }
      }
      amount = best;
    }
    if (amount == null) {
      // Last resort: the largest explicitly-currency-marked amount.
      double? best;
      for (final m in _currencyMoney.allMatches(text)) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v > 0 && (best == null || v > best)) best = v;
      }
      amount = best;
    }

    // Bills usually open with the store name — the first "wordy" line.
    merchant ??= lines.firstWhere(
      (l) =>
          RegExp(r'[A-Za-z]{3,}').hasMatch(l) &&
          !RegExp(r'\b(tax invoice|invoice|receipt|bill|gstin|phone|tel|date|time|order|welcome|cash memo)\b', caseSensitive: false).hasMatch(l) &&
          l.length <= 40,
      orElse: () => '',
    );
    if (merchant.isEmpty) merchant = null;
    if (merchant != null) {
      merchant = merchant.replaceAll(RegExp(r'[^\w &.\x27\-]'), '').trim();
      merchant = merchant.split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
    }

    final date = _date(text);
    final suggestions = EntrySuggestions(state);
    final mem = merchant == null ? null : suggestions.forMerchant(merchant);

    final receipt = ParsedTransaction(
      type: TransactionType.expense,
      amount: amount,
      merchant: merchant,
      categoryId: merchant == null ? null : suggestions.categoryFor(merchant),
      accountId: mem?.accountId,
      payCardId: mem?.payCardId,
      date: date,
      rawText: text,
    );
    // Prefer the bank-message read when the image was an alert screenshot.
    return asMessage == null ? receipt : asMessage.mergeMissingFrom(receipt);
  }

  DateTime? _date(String text) {
    final m = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').firstMatch(text);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) {
        final dt = DateTime(y, mo, d);
        if (!dt.isAfter(DateTime.now())) return dt;
      }
    }
    return null;
  }
}
