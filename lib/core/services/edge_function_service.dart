import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';
import '../database/finance_repository.dart';

class EdgeFunctionResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  EdgeFunctionResponse({required this.success, this.data, this.error});

  /// True only when the edge function returned HTTP 200 *and* an `ok: true`
  /// body. A 200 with `ok: false` (or no body) is treated as a failure so
  /// callers never mistake "the function ran" for "the work succeeded".
  bool get ok => success && (data?['ok'] == true);
}

class EdgeFunctionService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Serializes a transaction into the column shape the `transactions` cloud
  /// table (see supabase/migrations/0001_initial_cloud_schema.sql) expects.
  static Map<String, dynamic> _txRow(TransactionModel t) => {
        'id': t.id,
        'account_id': t.accountId,
        'to_account_id': t.toAccountId,
        'type': t.type.name,
        'amount': t.amount,
        'category_id': t.categoryId,
        'merchant': t.merchant,
        'date': t.date.toIso8601String(),
        'description': t.description,
        'notes': t.notes,
        'credit_card_id': t.creditCardId,
        'loan_id': t.loanId,
        'sync_status': 'synced',
      };

  static Map<String, dynamic> _accountRow(AccountModel a) => {
        'id': a.id,
        'name': a.name,
        'type': a.type.name,
        'bank': a.bank,
        'opening_balance': a.openingBalance,
        'calculated_balance': a.calculatedBalance,
        'currency': a.currency,
        'is_active': a.isActive,
        'created_at': a.createdAt.toIso8601String(),
      };

  /// Invoke Edge Function 'financial-summary'.
  static Future<EdgeFunctionResponse> fetchFinancialSummary({
    double? emergencyBuffer,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'financial-summary',
        body: emergencyBuffer != null
            ? {'emergency_buffer': emergencyBuffer}
            : null,
      );
      if (res.status == 200) {
        return EdgeFunctionResponse(
          success: true,
          data: (res.data as Map?)?.cast<String, dynamic>(),
        );
      }
      return EdgeFunctionResponse(
          success: false, error: 'Edge function status ${res.status}');
    } catch (e) {
      return EdgeFunctionResponse(success: false, error: e.toString());
    }
  }

  /// Full-state push to Edge Function 'sync-ledger'.
  static Future<EdgeFunctionResponse> syncLedger(FinanceState state) async {
    return _invokeSyncLedger({
      'accounts': state.accounts.map(_accountRow).toList(),
      'transactions': state.transactions.map(_txRow).toList(),
    });
  }

  /// Pushes the given pending (offline) transactions to 'sync-ledger' and
  /// returns the set of transaction ids the server confirmed it persisted.
  /// An empty set means nothing was synced (offline, auth failure, or a
  /// server error) — callers must NOT mark those transactions as synced.
  static Future<Set<String>> pushPendingTransactions(
    List<TransactionModel> pending,
  ) async {
    if (pending.isEmpty) return const {};
    final res = await _invokeSyncLedger({
      'transactions': pending.map(_txRow).toList(),
    });
    if (!res.ok) return const {};

    final ids = (res.data?['synced_ids'] as List?)?.whereType<String>().toSet();
    if (ids != null) return ids;
    // Server reported ok but didn't echo ids — trust the ok and take all.
    return pending.map((t) => t.id).toSet();
  }

  static Future<EdgeFunctionResponse> _invokeSyncLedger(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _client.functions.invoke('sync-ledger', body: payload);
      final data = (res.data as Map?)?.cast<String, dynamic>();
      if (res.status == 200) {
        return EdgeFunctionResponse(success: true, data: data);
      }
      return EdgeFunctionResponse(
        success: false,
        data: data,
        error: data?['error']?.toString() ?? 'Edge function status ${res.status}',
      );
    } catch (e) {
      return EdgeFunctionResponse(success: false, error: e.toString());
    }
  }
}
