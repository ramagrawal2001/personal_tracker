import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';

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

  /// The live auth session, or null. This — not [currentUser] — is the single
  /// source of truth for "is this user authenticated": a session carries a
  /// valid (auto-refreshed) access token; without one, no authenticated API
  /// call or cloud sync can succeed.
  static Session? get currentSession {
    if (!_isInitialized) return null;
    try {
      return client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  static bool get hasValidSession => currentSession != null;

  // There is no separate sync engine any more — `FinanceNotifier` /
  // `NotesNotifier` call this client directly for every mutation and for the
  // periodic `refreshFromCloud()` full fetch (see `lib/core/sync/
  // cloud_direct_write.dart` and CLAUDE.md's "direct writes" architecture
  // note). The old outbox / LWW-merge / realtime `SyncService` this comment
  // used to describe was removed.
}
