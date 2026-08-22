import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker/core/constants/app_constants.dart';
import 'package:personal_tracker/core/database/finance_repository.dart';
import 'package:personal_tracker/core/services/sync_engine.dart';
import 'package:personal_tracker/domain/models/models.dart';

void main() {
  group('Offline-First Sync Engine Tests', () {
    late FinanceNotifier financeNotifier;
    late SyncEngineNotifier syncNotifier;
    late String testAccountId;

    setUp(() {
      financeNotifier = FinanceNotifier();
      syncNotifier = SyncEngineNotifier();
      // Create a test account
      financeNotifier.addAccount(
        name: 'Test Account',
        type: AccountType.savingsAccount,
        openingBalance: 10000.0,
      );
      testAccountId = financeNotifier.state.accounts.first.id;
    });

    test('Adding transaction in offline mode assigns SyncStatus.pending', () {
      financeNotifier.addTransaction(
        accountId: testAccountId,
        type: TransactionType.expense,
        amount: 1200.0,
        merchant: 'Offline Store',
        date: DateTime.now(),
        isOnline: false,
      );

      final addedTx = financeNotifier.state.transactions.first;
      expect(addedTx.syncStatus, equals(SyncStatus.pending));
    });

    test('Network restoration automatically flushes pending offline transactions', () async {
      financeNotifier.addTransaction(
        accountId: testAccountId,
        type: TransactionType.expense,
        amount: 850.0,
        merchant: 'No-Network Cafe',
        date: DateTime.now(),
        isOnline: false,
      );

      final pendingList = financeNotifier.state.transactions
          .where((t) => t.syncStatus == SyncStatus.pending)
          .toList();
      expect(pendingList.isNotEmpty, isTrue);

      // Simulate network restoration (Offline -> Online)
      syncNotifier.toggleNetwork(true);

      final count = await syncNotifier.flushPendingQueue(
        pendingList,
        (id) => financeNotifier.markTransactionSynced(id),
      );

      expect(count, equals(pendingList.length));
      final remainingPending = financeNotifier.state.transactions
          .where((t) => t.syncStatus == SyncStatus.pending)
          .toList();
      expect(remainingPending, isEmpty);
    });
  });
}
