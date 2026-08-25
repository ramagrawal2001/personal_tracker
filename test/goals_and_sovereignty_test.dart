import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/backup_service.dart';
import 'package:aspyric/domain/models/models.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // BackupService's device key lives in the platform Keychain/Keystore via
  // flutter_secure_storage, which has no real implementation under
  // `flutter test`. Stub the channel with a simple in-memory map so the
  // encryption round-trip can be exercised without a device.
  final secureStorageValues = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      switch (call.method) {
        case 'read':
          return secureStorageValues[call.arguments['key']];
        case 'write':
          secureStorageValues[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'delete':
          secureStorageValues.remove(call.arguments['key']);
          return null;
        case 'containsKey':
          return secureStorageValues.containsKey(call.arguments['key']);
        default:
          return null;
      }
    },
  );

  group('Custom Savings Goals & Data Sovereignty Tests', () {
    late FinanceNotifier notifier;

    setUp(() {
      notifier = createTestFinanceNotifier();
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
      // Create a fresh goal directly via the notifier
      notifier.addGoal(
        name: 'Emergency Fund',
        targetAmount: 100000.0,
        currentSavedAmount: 50000.0,
        icon: 'shield',
      );

      final targetGoal = notifier.state.goals.first;
      final initialSaved = targetGoal.currentSavedAmount;

      notifier.addFundsToGoal(targetGoal.id, 10000.0);

      final updatedGoal = notifier.state.goals.firstWhere((g) => g.id == targetGoal.id);
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


    test('AES-256 Encrypted Local Vault Backup & Restore', () async {
      final stateData = {
        'netWorth': 842500.0,
        'totalAssets': 1000000.0,
        'testKey': 'LocalVaultSecret',
      };

      // Export Encrypted Backup
      final encryptedString = await BackupService.exportEncryptedBackup(stateData);
      expect(encryptedString.contains('checksum'), isTrue);
      expect(encryptedString.contains('payload'), isTrue);

      // Restore Encrypted Backup
      final restored = await BackupService.importEncryptedBackup(encryptedString);
      expect(restored, isNotNull);
      expect(restored!['netWorth'], equals(842500.0));
      expect(restored['testKey'], equals('LocalVaultSecret'));
    });

    test('Restoring a tampered backup fails its integrity check', () async {
      final encryptedString = await BackupService.exportEncryptedBackup({'a': 1});
      final tampered = encryptedString.replaceFirst('"checksum"', '"checksum_broken"');
      final restored = await BackupService.importEncryptedBackup(tampered);
      expect(restored, isNull);
    });
  });
}
