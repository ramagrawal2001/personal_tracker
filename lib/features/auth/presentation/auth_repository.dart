import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

/// Convert Supabase / Dart exceptions into friendly one-liners.
String _friendlyError(Object e) {
  if (e is AuthApiException) {
    switch (e.code) {
      case 'invalid_credentials':  return 'Incorrect email or password.';
      case 'user_not_found':       return 'No account found with this email.';
      case 'email_not_confirmed':  return 'Email not verified. Check your inbox.';
      case 'over_email_send_rate_limit':
      case 'email_rate_limit_exceeded':
        return 'Too many attempts. Please wait a minute and try again.';
      case 'email_address_invalid':
      case 'invalid_email':        return 'Please enter a valid email address.';
      case 'weak_password':        return 'Password is too weak. Use at least 8 characters.';
      case 'user_already_exists':
      case 'email_exists':         return 'An account with this email already exists.';
      default:
        return e.message.isNotEmpty ? e.message : 'Authentication error. Please try again.';
    }
  }
  final msg = e.toString();
  // Strip "Exception: " prefix if present
  if (msg.startsWith('Exception: ')) return msg.substring(11);
  return 'Something went wrong. Please try again.';
}

class AuthState {
  final bool isAuthenticated;
  final User? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState({
    required this.isAuthenticated,
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier()
      : super(
          AuthState(
            isAuthenticated: SupabaseService.currentUser != null,
            user: SupabaseService.currentUser,
          ),
        );



  void clearError() => state = state.copyWith(errorMessage: null);

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        state = state.copyWith(
          isAuthenticated: true,
          user: response.user,
          isLoading: false,
        );
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Sign in failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _friendlyError(e));
      return false;
    }
  }

  Future<bool> signUp(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user != null) {
        state = state.copyWith(
          isAuthenticated: true,
          user: response.user,
          isLoading: false,
        );
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Sign up failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _friendlyError(e));
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {}
    state = AuthState(isAuthenticated: false);
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
