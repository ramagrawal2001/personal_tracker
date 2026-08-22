import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/core/database/finance_repository.dart';

void main() {
  group('User Account Data Isolation Tests', () {
    late FinanceNotifier notifier;

    setUp(() {
      notifier = FinanceNotifier();
    });

    test('New account registration initializes clean state without pre-populated mock figures', () {
      // Simulate new user registration with user ID 'usr_new_789'
      notifier.clearForNewUser('usr_new_789');

      expect(notifier.state.transactions, isEmpty);
      expect(notifier.state.creditCards, isEmpty);
      expect(notifier.state.loans, isEmpty);
      expect(notifier.state.investments, isEmpty);
      expect(notifier.state.goals, isEmpty);
      expect(notifier.state.totalAssets, equals(0.0));
      expect(notifier.state.netWorth, equals(0.0));
      expect(notifier.state.isBiometricEnabled, isFalse);
    });
  });
}
