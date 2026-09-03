import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// A change observed on a remote table (used by Phase 3 realtime).
class RemoteChange {
  final String table;
  final String op; // 'insert' | 'update' | 'delete'
  final Map<String, dynamic> row;
  final DateTime updatedAt;

  const RemoteChange({
    required this.table,
    required this.op,
    required this.row,
    required this.updatedAt,
  });
}

/// Retryable failure — network down, timeout, free-tier project paused.
class SyncTransientError implements Exception {
  final String message;
  SyncTransientError(this.message);
  @override
  String toString() => 'SyncTransientError: $message';
}

/// Non-retryable failure — RLS rejection, bad payload, auth revoked.
class SyncPermanentError implements Exception {
  final String message;
  SyncPermanentError(this.message);
  @override
  String toString() => 'SyncPermanentError: $message';
}

/// The single testability seam between [SyncService] and Supabase. Phase 1
/// only exercises [isAvailable] + [upsertRow]; [pull] / [subscribe] /
/// [unsubscribe] / [connectionState] are declared here so Phase 2/3 can fill
/// them without touching call sites.
abstract class CloudGateway {
  bool get isAvailable;

  Future<DateTime> upsertRow(String table, Map<String, dynamic> row);

  Future<List<Map<String, dynamic>>> pull(
    String table, {
    DateTime? since,
    int limit,
    int offset,
  });

  Stream<RemoteChange> subscribe(String userId, List<String> tables);

  Future<void> unsubscribe();

  Object get connectionState;
}

/// Production gateway. Talks directly to Supabase; RLS + `user_id default
/// auth.uid()` scope every row to the signed-in user.
class SupabaseCloudGateway implements CloudGateway {
  @override
  bool get isAvailable {
    try {
      return SupabaseService.isInitialized &&
          SupabaseService.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DateTime> upsertRow(String table, Map<String, dynamic> row) async {
    try {
      final res = await SupabaseService.client
          .from(table)
          .upsert(row, onConflict: table == 'user_settings' ? 'user_id' : 'user_id,id')
          .select('updated_at')
          .single();
      final ts = res['updated_at'];
      if (ts is String) return DateTime.parse(ts).toLocal();
      return DateTime.now();
    } on SocketException catch (e) {
      throw SyncTransientError(e.toString());
    } on TimeoutException catch (e) {
      throw SyncTransientError(e.toString());
    } on PostgrestException catch (e) {
      // A dropped connection sometimes surfaces here without a status code.
      if (e.code == null && _looksTransient(e.message)) {
        throw SyncTransientError(e.message);
      }
      throw SyncPermanentError('${e.code}: ${e.message}');
    } on AuthException catch (e) {
      throw SyncPermanentError(e.message);
    } catch (e) {
      if (_looksTransient(e.toString())) throw SyncTransientError(e.toString());
      rethrow;
    }
  }

  bool _looksTransient(String m) {
    final s = m.toLowerCase();
    return s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('connection') ||
        s.contains('network') ||
        s.contains('failed host lookup');
  }

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    DateTime? since,
    int limit = 500,
    int offset = 0,
  }) =>
      throw UnimplementedError('CloudGateway.pull is Phase 2');

  @override
  Stream<RemoteChange> subscribe(String userId, List<String> tables) =>
      throw UnimplementedError('CloudGateway.subscribe is Phase 3');

  @override
  Future<void> unsubscribe() =>
      throw UnimplementedError('CloudGateway.unsubscribe is Phase 3');

  @override
  Object get connectionState => 'unknown';
}
