import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// A change observed on a remote table (used by Phase 3 realtime).
class RemoteChange {
  final String table;
  final String op; // 'upsert' | 'delete'
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

/// The single testability seam between [SyncService] and Supabase.
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

  /// True when the realtime websocket is currently connected.
  bool get isSocketConnected;
}

/// Production gateway. Talks directly to Supabase; RLS + `user_id default
/// auth.uid()` scope every row to the signed-in user.
class SupabaseCloudGateway implements CloudGateway {
  RealtimeChannel? _channel;
  StreamController<RemoteChange>? _controller;

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
  Future<DateTime> upsertRow(String table, Map<String, dynamic> row) {
    return _guarded(() async {
      final res = await SupabaseService.client
          .from(table)
          .upsert(row, onConflict: table == 'user_settings' ? 'user_id' : 'user_id,id')
          .select('updated_at')
          .single();
      final ts = res['updated_at'];
      if (ts is String) return DateTime.parse(ts).toLocal();
      return DateTime.now();
    });
  }

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    DateTime? since,
    int limit = 500,
    int offset = 0,
  }) {
    return _guarded(() async {
      final base = SupabaseService.client.from(table).select();
      final filtered = since != null
          ? base.gt('updated_at', since.toUtc().toIso8601String())
          : base;
      final res = await filtered
          .order('updated_at', ascending: true)
          .range(offset, offset + limit - 1);
      return (res as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    });
  }

  /// Shared error classification used by every network call (mirrors the
  /// original inline logic in [upsertRow]).
  Future<T> _guarded<T>(Future<T> Function() op) async {
    try {
      return await op();
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
  Stream<RemoteChange> subscribe(String userId, List<String> tables) {
    // Tear down any previous subscription first.
    unawaited(unsubscribe());
    final controller = StreamController<RemoteChange>.broadcast();
    _controller = controller;

    try {
      var channel = SupabaseService.client.channel('sync:$userId');
      for (final t in tables) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _emit(controller, t, payload),
        );
      }
      channel.subscribe((status, error) {
        if (error != null) {
          debugPrint('SupabaseCloudGateway: channel $status error: $error');
        }
      });
      _channel = channel;
    } catch (e, st) {
      debugPrint('SupabaseCloudGateway.subscribe failed: $e\n$st');
    }

    return controller.stream;
  }

  void _emit(
    StreamController<RemoteChange> controller,
    String table,
    PostgresChangePayload payload,
  ) {
    try {
      if (controller.isClosed) return;
      final record = payload.newRecord.isNotEmpty
          ? payload.newRecord
          : payload.oldRecord;
      final row = record.cast<String, dynamic>();
      final deleted = row['is_deleted'] == true ||
          payload.eventType == PostgresChangeEvent.delete;
      DateTime updatedAt;
      final raw = row['updated_at'];
      if (raw is String) {
        updatedAt = DateTime.parse(raw).toLocal();
      } else {
        updatedAt = payload.commitTimestamp.toLocal();
      }
      controller.add(RemoteChange(
        table: table,
        op: deleted ? 'delete' : 'upsert',
        row: row,
        updatedAt: updatedAt,
      ));
    } catch (e, st) {
      debugPrint('SupabaseCloudGateway._emit failed: $e\n$st');
    }
  }

  @override
  Future<void> unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await SupabaseService.client.removeChannel(channel);
      } catch (e) {
        debugPrint('SupabaseCloudGateway.unsubscribe removeChannel failed: $e');
      }
    }
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  @override
  Object get connectionState {
    try {
      return SupabaseService.client.realtime.connectionState;
    } catch (_) {
      return 'unknown';
    }
  }

  @override
  bool get isSocketConnected {
    try {
      return SupabaseService.client.realtime.isConnected;
    } catch (_) {
      return false;
    }
  }
}
