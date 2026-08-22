import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/core/database/finance_repository.dart';
import 'package:personal_tracker/core/services/backup_service.dart';
import 'package:personal_tracker/domain/models/models.dart';

void main() {
  group('Custom Savings Goals & Data Sovereignty Tests', () {
    late FinanceNotifier notifier;

    setUp(() {
      notifier = FinanceNotifier();
    });

    test('Savings Goal progress calculation', () {
      final goal = GoalModel(
        id: '1',
        name: 'MacBook',
        targetAmount: 200000.0,
        currentSavedAmount: 150000.0,
      );

      expect(goal.progressPercentage, equals(0.75));
      expect(goal.remainingAmount, equals(50000.0));
    });

    test('Add Funds to Savings Goal', () {
      final initialSaved = notifier.state.goals.first.currentSavedAmount;
      final targetGoalId = notifier.state.goals.first.id;

      notifier.addFundsToGoal(targetGoalId, 10000.0);

      final updatedGoal = notifier.state.goals.firstWhere((g) => g.id == targetGoalId);
      expect(updatedGoal.currentSavedAmount, equals(initialSaved + 10000.0));
    });

    test('Profile Feature Toggles (Biometrics, Round-ups, Auto-Backup)', () {
      expect(notifier.state.isBiometricEnabled, isFalse);

      notifier.toggleBiometric(true);
      expect(notifier.state.isBiometricEnabled, isTrue);

      notifier.toggleRoundUp(false);
      expect(notifier.state.isRoundUpEnabled, isFalse);

      notifier.toggleAutoBackup(false);
      expect(notifier.state.isAutoBackupEnabled, isFalse);
    });


    test('100% Encrypted Local Database Backup & Restore', () {
      final stateData = {
        'netWorth': 842500.0,
        'totalAssets': 1000000.0,
        'testKey': 'LocalVaultSecret',
      };

      // Export Encrypted Backup
      final encryptedString = BackupService.exportEncryptedBackup(stateData);
      expect(encryptedString.contains('checksum'), isTrue);
      expect(encryptedString.contains('payload'), isTrue);

      // Restore Encrypted Backup
      final restored = BackupService.importEncryptedBackup(encryptedString);
      expect(restored, isNotNull);
      expect(restored!['netWorth'], equals(842500.0));
      expect(restored['testKey'], equals('LocalVaultSecret'));
    });
  });
}
