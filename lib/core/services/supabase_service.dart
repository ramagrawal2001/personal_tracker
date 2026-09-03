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

  // Cloud sync now lives in lib/core/sync/ (SyncService + the offline outbox).
  // The old fire-and-forget syncLocalDataToCloud / EdgeFunctionService /
  // SyncEngineNotifier paths were removed in the Phase 4 cleanup.
}
