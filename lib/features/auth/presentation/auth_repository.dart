import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

const _kSessionIsLoggedIn = 'aspyric_session_logged_in';
const _kSessionUserId     = 'aspyric_session_user_id';
const _kSessionUserEmail  = 'aspyric_session_user_email';
const _kSessionUserName   = 'aspyric_session_user_name';

/// ── Demo / test account bypass ───────────────────────────────────────────────
/// These credentials work offline without Supabase.
/// Password for all test accounts: Aspyric@123
const Map<String, String> _demoAccounts = {
  'test@aspyric.app'  : 'Aspyric@123',
  'demo@aspyric.app'  : 'Aspyric@123',
  'admin@aspyric.app' : 'Aspyric@123',
};

/// Convert Supabase / Dart exceptions into friendly one-liners.
String _friendlyError(Object e) {
  if (e is AuthApiException) {
    switch (e.code) {
      case 'invalid_credentials':  return 'Incorrect email or password.';
      case 'user_not_found':       return 'No account found with this email.';
      case 'email_not_confirmed':  return 'Email not verified. Check your inbox.';
      case 'over_email_send_rate_limit':
      case 'email_rate_limit_exceeded':
      case 'over_request_rate_limit':
        return 'Too many attempts. If you already signed up, please tap Sign In with your password.';
      case 'email_address_invalid':
      case 'invalid_email':        return 'Please enter a valid email address.';
      case 'weak_password':        return 'Password is too weak. Use at least 6 characters.';
      case 'user_already_exists':
      case 'email_exists':         return 'An account with this email already exists. Please tap Sign In.';
      default:
        return e.message.isNotEmpty ? e.message : 'Authentication error. Please try again.';
    }
  }
  final msg = e.toString();
  if (msg.startsWith('Exception: ')) return msg.substring(11);
  return 'Something went wrong. Please try again.';
}

class AuthState {
  final bool isAuthenticated;
  final User? user;
  final bool isLoading;
  final bool isRestored;
  final String? errorMessage;

  AuthState({
    required this.isAuthenticated,
    this.user,
    this.isLoading = false,
    this.isRestored = false,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isLoading,
    bool? isRestored,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isRestored: isRestored ?? this.isRestored,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  StreamSubscription<AuthState>? _supabaseSub;
  Completer<void>? _restoreCompleter;

  AuthNotifier()
      : super(
          AuthState(
            isAuthenticated: SupabaseService.currentUser != null,
            user: SupabaseService.currentUser,
            isRestored: false,
          ),
        ) {
    _init();
  }

  void _init() {
    _listenToSupabase();
    ensureSessionRestored();
  }

  void _listenToSupabase() {
    if (!SupabaseService.isInitialized) return;
    try {
      SupabaseService.client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        if (session != null) {
          _persistSession(
            email: session.user.email ?? '',
            userId: session.user.id,
            name: session.user.userMetadata?['full_name'] as String?,
          );
          state = state.copyWith(
            isAuthenticated: true,
            user: session.user,
            isRestored: true,
          );
        } else if (data.event == AuthChangeEvent.signedOut) {
          _clearPersistedSession();
          state = AuthState(isAuthenticated: false, isRestored: true);
        }
      });
    } catch (_) {}
  }

  Future<void> ensureSessionRestored() async {
    if (_restoreCompleter != null) return _restoreCompleter!.future;
    _restoreCompleter = Completer<void>();

    try {
      // 1. Check active Supabase current user
      final currentSbUser = SupabaseService.currentUser;
      if (currentSbUser != null) {
        await _persistSession(
          email: currentSbUser.email ?? '',
          userId: currentSbUser.id,
          name: currentSbUser.userMetadata?['full_name'] as String?,
        );
        state = state.copyWith(
          isAuthenticated: true,
          user: currentSbUser,
          isRestored: true,
        );
        _restoreCompleter?.complete();
        return;
      }

      // 2. Check local SharedPreferences session
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(_kSessionIsLoggedIn) ?? false;
      final savedEmail = prefs.getString(_kSessionUserEmail);
      final savedId = prefs.getString(_kSessionUserId);
      final savedName = prefs.getString(_kSessionUserName);

      if (isLoggedIn && savedEmail != null && savedEmail.isNotEmpty) {
        final restoredUser = User(
          id: savedId ?? 'user_${savedEmail.hashCode}',
          appMetadata: const {},
          userMetadata: {'full_name': savedName ?? ''},
          aud: 'authenticated',
          email: savedEmail,
          createdAt: DateTime.now().toIso8601String(),
        );

        state = state.copyWith(
          isAuthenticated: true,
          user: restoredUser,
          isRestored: true,
        );
      } else {
        state = state.copyWith(
          isAuthenticated: false,
          isRestored: true,
        );
      }
    } catch (e) {
      state = state.copyWith(isRestored: true);
    } finally {
      if (!(_restoreCompleter?.isCompleted ?? true)) {
        _restoreCompleter?.complete();
      }
    }
  }

  Future<void> _persistSession({
    required String email,
    required String userId,
    String? name,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSessionIsLoggedIn, true);
      await prefs.setString(_kSessionUserEmail, email);
      await prefs.setString(_kSessionUserId, userId);
      if (name != null) {
        await prefs.setString(_kSessionUserName, name);
      }
    } catch (_) {}
  }

  Future<void> _clearPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSessionIsLoggedIn);
      await prefs.remove(_kSessionUserEmail);
      await prefs.remove(_kSessionUserId);
      await prefs.remove(_kSessionUserName);
    } catch (_) {}
  }

  void clearError() => state = state.copyWith(errorMessage: null);

  /// Explicitly activates and persists an authenticated user session (e.g. after Resend OTP verification)
  Future<void> activateSession({
    required String email,
    String? userId,
    String? name,
  }) async {
    final uid = userId ?? 'user_${email.trim().toLowerCase().hashCode}';
    final user = User(
      id: uid,
      appMetadata: const {},
      userMetadata: {'full_name': name ?? ''},
      aud: 'authenticated',
      email: email.trim().toLowerCase(),
      createdAt: DateTime.now().toIso8601String(),
    );

    await _persistSession(
      email: email.trim().toLowerCase(),
      userId: uid,
      name: name,
    );

    state = state.copyWith(
      isAuthenticated: true,
      user: user,
      isLoading: false,
      errorMessage: null,
      isRestored: true,
    );
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final normalised = email.trim().toLowerCase();

    // ── Demo / test bypass ─────────────────────────────────────────────────
    if (_demoAccounts[normalised] == password) {
      await Future.delayed(const Duration(milliseconds: 300));
      await activateSession(
        email: normalised,
        userId: 'demo_${normalised.hashCode}',
        name: normalised.split('@').first.toUpperCase(),
      );
      return true;
    }
    // ───────────────────────────────────────────────────────────────────────

    try {
      if (SupabaseService.isInitialized) {
        final response = await SupabaseService.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (response.user != null) {
          await _persistSession(
            email: response.user!.email ?? email,
            userId: response.user!.id,
            name: response.user!.userMetadata?['full_name'] as String?,
          );
          state = state.copyWith(
            isAuthenticated: true,
            user: response.user,
            isLoading: false,
          );
          return true;
        }
      }

      // If Supabase not initialized or returned null, activate session locally
      await activateSession(email: email);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _friendlyError(e));
      return false;
    }
  }

  Future<bool> signUp(String email, String password, {String? name}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      if (SupabaseService.isInitialized) {
        final response = await SupabaseService.client.auth.signUp(
          email: email,
          password: password,
          data: name != null ? {'full_name': name} : null,
        );
        if (response.user != null) {
          await _persistSession(
            email: response.user!.email ?? email,
            userId: response.user!.id,
            name: name,
          );
          state = state.copyWith(
            isAuthenticated: true,
            user: response.user,
            isLoading: false,
          );
          return true;
        }
      }

      // If Supabase is offline or email confirmation bypass, activate session locally
      await activateSession(email: email, name: name);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _friendlyError(e));
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      if (SupabaseService.isInitialized) {
        await SupabaseService.client.auth.signOut();
      }
    } catch (_) {}
    await _clearPersistedSession();
    state = AuthState(isAuthenticated: false, isRestored: true);
  }

  @override
  void dispose() {
    _supabaseSub?.cancel();
    super.dispose();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
