import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/finance_repository.dart';

class EdgeFunctionResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  EdgeFunctionResponse({required this.success, this.data, this.error});
}

class EdgeFunctionService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Invoke Edge Function 'financial-summary'
  static Future<EdgeFunctionResponse> fetchFinancialSummary() async {
    try {
      final res = await _client.functions.invoke('financial-summary');
      if (res.status == 200) {
        return EdgeFunctionResponse(success: true, data: res.data as Map<String, dynamic>?);
      }
      return EdgeFunctionResponse(success: false, error: 'Edge function status ${res.status}');
    } catch (e) {
      return EdgeFunctionResponse(success: false, error: e.toString());
    }
  }

  /// Invoke Edge Function 'sync-ledger' with local payload
  static Future<EdgeFunctionResponse> syncLedger(FinanceState state) async {
    try {
      final payload = {
        'accounts': state.accounts.map((a) => {
          'id': a.id,
          'name': a.name,
          'type': a.type.name,
          'opening_balance': a.openingBalance,
          'calculated_balance': a.calculatedBalance,
        }).toList(),
        'transactions': state.transactions.map((t) => {
          'id': t.id,
          'account_id': t.accountId,
          'type': t.type.name,
          'amount': t.amount,
          'merchant': t.merchant,
          'date': t.date.toIso8601String(),
        }).toList(),
      };

      final res = await _client.functions.invoke('sync-ledger', body: payload);
      if (res.status == 200) {
        return EdgeFunctionResponse(success: true, data: res.data as Map<String, dynamic>?);
      }
      return EdgeFunctionResponse(success: false, error: 'Edge function status ${res.status}');
    } catch (e) {
      return EdgeFunctionResponse(success: false, error: e.toString());
    }
  }

  /// Invoke Edge Function 'sync-ledger' for a single offline transaction item
  static Future<EdgeFunctionResponse> syncLedgerItem({
    required String transactionId,
    required double amount,
    required String type,
  }) async {
    try {
      final payload = {
        'transaction_id': transactionId,
        'amount': amount,
        'type': type,
      };
      final res = await _client.functions.invoke('sync-ledger', body: payload);
      if (res.status == 200) {
        return EdgeFunctionResponse(success: true, data: res.data as Map<String, dynamic>?);
      }
      return EdgeFunctionResponse(success: false, error: 'Edge function status ${res.status}');
    } catch (e) {
      return EdgeFunctionResponse(success: false, error: e.toString());
    }
  }
}
