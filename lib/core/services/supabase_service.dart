import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';
import '../database/finance_repository.dart';

class SupabaseService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        publishableKey: EnvConfig.supabaseAnonKey,
      );

      _isInitialized = true;
    } catch (e) {
      // Fallback gracefully if offline or mock key environment
      debugPrint('SupabaseService: initialize() failed, continuing offline: $e');
      _isInitialized = false;
    }
  }

  static bool get isInitialized => _isInitialized;
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser {
    if (!_isInitialized) return null;
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }


  /// Sync local SQLite Finance state to Supabase PostgreSQL database
  static Future<bool> syncLocalDataToCloud(FinanceState state) async {
    if (!_isInitialized) return false;

    try {
      // 1. Sync Accounts
      for (var acc in state.accounts) {
        await client.from('accounts').upsert({
          'id': acc.id,
          'name': acc.name,
          'type': acc.type.name,
          'bank': acc.bank,
          'opening_balance': acc.openingBalance,
          'calculated_balance': acc.calculatedBalance,
          'created_at': acc.createdAt.toIso8601String(),
        });
      }

      // 2. Sync Transactions
      for (var tx in state.transactions) {
        await client.from('transactions').upsert({
          'id': tx.id,
          'account_id': tx.accountId,
          'to_account_id': tx.toAccountId,
          'type': tx.type.name,
          'amount': tx.amount,
          'category_id': tx.categoryId,
          'merchant': tx.merchant,
          'date': tx.date.toIso8601String(),
          'description': tx.description,
        });
      }

      return true;
    } catch (e) {
      debugPrint('SupabaseService: syncLocalDataToCloud failed: $e');
      return false;
    }
  }
}
