import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

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
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
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
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
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
