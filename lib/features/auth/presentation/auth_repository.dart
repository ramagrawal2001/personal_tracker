import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/secret_cipher_service.dart';

const _kSessionIsLoggedIn = 'aspyric_session_logged_in';
const _kSessionUserId     = 'aspyric_session_user_id';
const _kSessionUserEmail  = 'aspyric_session_user_email';
const _kSessionUserName   = 'aspyric_session_user_name';

/// ── Demo / test account bypass ───────────────────────────────────────────────
/// These credentials work offline without Supabase, but ONLY in debug builds
/// (see the `kDebugMode` guard in `signIn`) — `flutter build` release/profile
/// binaries never compile this bypass into a reachable code path.
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

  /// Used to reach [secretCipherServiceProvider] at the points where the
  /// plaintext password is briefly in hand (sign-in / sign-up).
  final Ref _ref;

  AuthNotifier(this._ref)
      : super(
          AuthState(
            // Authenticated == a live Supabase session (valid access token).
            isAuthenticated: SupabaseService.hasValidSession,
            user: SupabaseService.currentSession?.user,
            isRestored: false,
          ),
        ) {
    _init();
  }

  /// Debug-only: a demo/test account is active locally (no Supabase session).
  /// Release builds never set this, so authentication there is purely
  /// session-token driven.
  bool _demoSessionActive = false;

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
        } else if (!_demoSessionActive &&
            (data.event == AuthChangeEvent.signedOut ||
                data.event == AuthChangeEvent.tokenRefreshed)) {
          // Session is null on signedOut, or on a tokenRefreshed that failed →
          // force sign-out so the router bounces to /login and nothing runs
          // without a token. (A live debug demo session is left alone.)
          _clearPersistedSession();
          state = AuthState(isAuthenticated: false, isRestored: true);
        }
      });
    } catch (e) {
      debugPrint('AuthNotifier: failed to attach Supabase auth listener: $e');
    }
  }

  Future<void> ensureSessionRestored() async {
    if (_restoreCompleter != null) return _restoreCompleter!.future;
    _restoreCompleter = Completer<void>();

    try {
      // 1. A live Supabase session (token) is the only real authentication.
      //    supabase_flutter restores + auto-refreshes it from secure storage;
      //    if the refresh token is dead, currentSession is null here.
      final session = SupabaseService.currentSession;
      if (session != null) {
        await _persistSession(
          email: session.user.email ?? '',
          userId: session.user.id,
          name: session.user.userMetadata?['full_name'] as String?,
        );
        state = state.copyWith(
          isAuthenticated: true,
          user: session.user,
          isRestored: true,
        );
        _restoreCompleter?.complete();
        return;
      }

      // 2. Local SharedPreferences fallback — ONLY for debug-build demo
      //    accounts. A real user with a stale flag but no session is NOT
      //    authenticated; clear the flag so they land on /login.
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(_kSessionIsLoggedIn) ?? false;
      final savedEmail = prefs.getString(_kSessionUserEmail);
      final savedId = prefs.getString(_kSessionUserId);
      final savedName = prefs.getString(_kSessionUserName);

      final isDemo = kDebugMode &&
          savedEmail != null &&
          _demoAccounts.containsKey(savedEmail.trim().toLowerCase());

      if (isLoggedIn && isDemo) {
        _demoSessionActive = true;
        state = state.copyWith(
          isAuthenticated: true,
          user: User(
            id: savedId ?? 'user_${savedEmail.hashCode}',
            appMetadata: const {},
            userMetadata: {'full_name': savedName ?? ''},
            aud: 'authenticated',
            email: savedEmail,
            createdAt: DateTime.now().toIso8601String(),
          ),
          isRestored: true,
        );
      } else {
        if (isLoggedIn) await _clearPersistedSession();
        _demoSessionActive = false;
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
    } catch (e) {
      debugPrint('AuthNotifier: failed to persist session: $e');
    }
  }

  Future<void> _clearPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSessionIsLoggedIn);
      await prefs.remove(_kSessionUserEmail);
      await prefs.remove(_kSessionUserId);
      await prefs.remove(_kSessionUserName);
    } catch (e) {
      debugPrint('AuthNotifier: failed to clear persisted session: $e');
    }
  }

  void clearError() => state = state.copyWith(errorMessage: null);

  /// Debug-only local sign-in for demo/test accounts. Real authentication must
  /// go through [signIn] / [signUp] and produce a Supabase session; in release
  /// builds this is a no-op.
  Future<void> activateSession({
    required String email,
    String? userId,
    String? name,
  }) async {
    if (!kDebugMode) return;
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

    // ── Demo / test bypass (debug builds only) ──────────────────────────────
    if (kDebugMode && _demoAccounts[normalised] == password) {
      await Future.delayed(const Duration(milliseconds: 300));
      _demoSessionActive = true;
      final demoUid = 'demo_${normalised.hashCode}';
      await activateSession(
        email: normalised,
        userId: demoUid,
        name: normalised.split('@').first.toUpperCase(),
      );
      await _initSecretCipher(demoUid, password, isDemo: true);
      return true;
    }
    // ───────────────────────────────────────────────────────────────────────

    if (!SupabaseService.isInitialized) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Can\'t reach the server. Check your connection and try again.',
      );
      return false;
    }

    try {
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // A session (token) is mandatory — a user without one is not signed in.
      if (response.session != null) {
        state = state.copyWith(
          isAuthenticated: true,
          user: response.session!.user,
          isLoading: false,
        );
        await _initSecretCipher(response.session!.user.id, password);
        return true;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Email not verified. Check your inbox, then sign in.',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _friendlyError(e));
      return false;
    }
  }

  Future<bool> signUp(String email, String password, {String? name}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    if (!SupabaseService.isInitialized) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Can\'t reach the server. Check your connection and try again.',
      );
      return false;
    }

    try {
      final response = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
        data: name != null ? {'full_name': name} : null,
      );

      // Signed in only if Supabase returned a real session. When the project
      // has "Confirm email" on, signUp yields a user but no session — the
      // account exists, but there is no token, so the user is NOT authenticated.
      if (response.session != null) {
        state = state.copyWith(
          isAuthenticated: true,
          user: response.session!.user,
          isLoading: false,
        );
        await _initSecretCipher(response.session!.user.id, password, isSignup: true);
        return true;
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Account created. Please confirm your email from your inbox, then sign in.',
      );
      return false;
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
    } catch (e) {
      debugPrint('AuthNotifier: Supabase sign-out failed (clearing local session anyway): $e');
    }
    _demoSessionActive = false;
    // Forget the cached field-encryption DEK. The cloud wrappers stay, so the
    // same user re-logging-in on this device restores it automatically.
    await SecretCipherService.clearCachedDek();
    await _clearPersistedSession();
    state = AuthState(isAuthenticated: false, isRestored: true);
  }

  /// Bootstraps [SecretCipherService] with the plaintext password that is
  /// briefly available here. Failures are swallowed — encryption of new
  /// sensitive fields is simply skipped until the DEK is available.
  Future<void> _initSecretCipher(
    String userId,
    String password, {
    bool isSignup = false,
    bool isDemo = false,
  }) async {
    try {
      final cipher = _ref.read(secretCipherServiceProvider);
      if (isDemo) {
        await cipher.onLogin(userId, password, isDemo: true);
      } else if (isSignup) {
        await cipher.onSignup(userId, password);
      } else {
        await cipher.onLogin(userId, password);
      }
    } catch (e) {
      debugPrint('AuthNotifier: secret cipher init failed: $e');
    }
  }

  @override
  void dispose() {
    _supabaseSub?.cancel();
    super.dispose();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
