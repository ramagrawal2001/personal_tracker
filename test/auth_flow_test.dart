import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/features/auth/presentation/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The provider is read without disposing the container on purpose: AuthNotifier
  // kicks off an async session-restore in its constructor, and disposing mid-flight
  // makes that pending future touch `state` after teardown.
  group('Authentication Flow Tests', () {
    test('Initial unauthenticated state requires real login', () {
      final container = ProviderContainer();
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.user, isNull);
    });

    test('Sign out resets state to unauthenticated', () async {
      final container = ProviderContainer();
      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.signOut();
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.user, isNull);
    });
  });
}
