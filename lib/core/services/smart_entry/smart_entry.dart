import 'package:flutter/foundation.dart';

import '../../database/finance_repository.dart' show FinanceState;
import 'ai_transaction_service.dart';
import 'bank_message_parser.dart';
import 'parsed_transaction.dart';
import 'receipt_parser.dart';
import 'transaction_text_parser.dart';

class SmartEntryResult {
  final ParsedTransaction draft;
  final bool usedAi;

  /// Set when AI was configured but failed — the offline parse was used.
  final String? aiError;

  const SmartEntryResult(this.draft, {this.usedAi = false, this.aiError});
}

/// One entry point for "understand this text": the offline parser always
/// runs; when a free AI provider is configured its answer is layered on top
/// (AI wins per-field, the offline parse fills anything it left out).
class SmartEntry {
  SmartEntry._();

  static Future<SmartEntryResult> fromText(
    String text,
    FinanceState state, {
    CaptureSource source = CaptureSource.typed,
    bool allowAi = true,
  }) async {
    // A shared / forwarded / pasted bank alert parses best as a message; a
    // short typed or spoken note ("paid rs 500 cash") as a note.
    final messageLike = switch (source) {
      CaptureSource.sms || CaptureSource.notification || CaptureSource.shortcut || CaptureSource.share => true,
      CaptureSource.typed => text.length > 60,
      _ => false,
    };
    final asMessage = messageLike && BankMessageParser.looksTransactional(text) ? BankMessageParser(state).parse(text) : null;
    final local = source == CaptureSource.receipt
        ? ReceiptParser(state).parse(text)
        : asMessage ?? TransactionTextParser(state).parse(text, source: source);
    if (!allowAi || !await AiTransactionService.isUsable()) return SmartEntryResult(local);
    try {
      final ai = await AiTransactionService.parseTransaction(text, state, source: source);
      return SmartEntryResult(ai.mergeMissingFrom(local), usedAi: true);
    } catch (e) {
      debugPrint('SmartEntry: AI parse failed, using offline parse: $e');
      return SmartEntryResult(local, aiError: e.toString());
    }
  }
}
