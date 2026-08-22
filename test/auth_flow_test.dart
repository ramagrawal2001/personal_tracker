import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/features/auth/presentation/auth_repository.dart';

void main() {
  group('Authentication Flow Tests', () {
    test('Initial unauthenticated state', () {
      final notifier = AuthNotifier();
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.isGuestMode, isFalse);
      expect(notifier.state.user, isNull);
    });

    test('Continue as Guest mode updates state correctly', () {
      final notifier = AuthNotifier();
      notifier.continueAsGuest();

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.isGuestMode, isTrue);
      expect(notifier.state.user, isNull);
    });

    test('Sign out resets state to unauthenticated', () async {
      final notifier = AuthNotifier();
      notifier.continueAsGuest();
      expect(notifier.state.isAuthenticated, isTrue);

      await notifier.signOut();
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.isGuestMode, isFalse);
      expect(notifier.state.user, isNull);
    });
  });
}
