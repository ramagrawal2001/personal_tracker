import 'package:flutter/foundation.dart';

import '../services/supabase_service.dart';

/// Thrown by [CloudDirectWrite.pushToCloud] when a write to Supabase fails
/// while a real cloud session is active (network down, RLS rejection, a
/// paused free-tier project, ...). The UI layer catches this and shows the
/// message directly — there is no outbox / retry queue any more, so a failed
/// write must be surfaced immediately rather than silently queued.
class CloudWriteException implements Exception {
  final String message;
  CloudWriteException(this.message);
  @override
  String toString() => message;
}

/// Mixed into [FinanceNotifier] and [NotesNotifier]. Every mutator pushes its
/// row straight to Supabase *before* touching local state (see CLAUDE.md's
/// "direct writes" architecture note) — there is no outbox, no background
/// retry, no LWW merge any more. A failed push throws [CloudWriteException],
/// local Drift / in-memory state are left completely untouched, and the
/// caller (a UI mutator awaiting this) surfaces the error, e.g. a SnackBar.
mixin CloudDirectWrite {
  /// True only for a real, signed-in Supabase session — false for the
  /// debug-only demo/test accounts (`test@aspyric.app` et al.), which never
  /// touch Supabase and must keep working purely on local Drift, exactly as
  /// before this migration.
  bool get hasCloudSession {
    try {
      return SupabaseService.isInitialized && SupabaseService.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  /// Upserts [row] into the Supabase [table] and returns the server-assigned
  /// `updated_at` (parsed to local time) — same upsert shape the old
  /// `SupabaseCloudGateway.upsertRow` used for the outbox, so RLS / conflict
  /// targets are unchanged. Returns null (meaning: proceed local-only, no
  /// cloud to write to) when there is no session at all. Throws
  /// [CloudWriteException] when a session exists but the push itself fails.
  Future<DateTime?> pushToCloud(String table, Map<String, dynamic> row) async {
    if (!hasCloudSession) return null;
    try {
      final res = await SupabaseService.client
          .from(table)
          .upsert(row, onConflict: table == 'user_settings' ? 'user_id' : 'user_id,id')
          .select('updated_at')
          .single();
      final ts = res['updated_at'];
      return ts is String ? DateTime.parse(ts).toLocal() : DateTime.now();
    } catch (e) {
      debugPrint('CloudDirectWrite.pushToCloud($table) failed: $e');
      throw CloudWriteException(_friendly(e));
    }
  }

  String _friendly(Object e) {
    final m = e.toString();
    if (m.contains('SocketException') || m.contains('Failed host lookup') || m.contains('Network is unreachable')) {
      return 'No internet connection. Please try again.';
    }
    if (m.contains('TimeoutException') || m.contains('timed out')) {
      return 'The request timed out. Please try again.';
    }
    return 'Could not save to the cloud: $m';
  }
}
