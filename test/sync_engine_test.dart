import 'package:flutter_test/flutter_test.dart';
import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:aspyric/core/services/sync_engine.dart';
import 'package:aspyric/domain/models/models.dart';
import 'test_helpers.dart';

void main() {
  group('Offline-First Sync Engine Tests', () {
    late FinanceNotifier financeNotifier;
    late SyncEngineNotifier syncNotifier;
    late String testAccountId;

    setUp(() {
      financeNotifier = createTestFinanceNotifier();
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

    test('Network restoration flushes pending transactions the server confirms', () async {
      // Stub the cloud push: confirm every id it is handed.
      syncNotifier = SyncEngineNotifier(
        pushPending: (pending) async => pending.map((t) => t.id).toSet(),
      );

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

    test('A failed cloud push leaves every transaction queued for retry', () async {
      // Stub the cloud push as failing: it confirms nothing.
      syncNotifier = SyncEngineNotifier(pushPending: (_) async => const {});

      financeNotifier.addTransaction(
        accountId: testAccountId,
        type: TransactionType.expense,
        amount: 1499.0,
        merchant: 'Server-Down Store',
        date: DateTime.now(),
        isOnline: false,
      );

      final pendingList = financeNotifier.state.transactions
          .where((t) => t.syncStatus == SyncStatus.pending)
          .toList();
      expect(pendingList, isNotEmpty);

      syncNotifier.toggleNetwork(true);

      final count = await syncNotifier.flushPendingQueue(
        pendingList,
        (id) => financeNotifier.markTransactionSynced(id),
      );

      // Nothing was confirmed, so nothing is marked synced.
      expect(count, equals(0));
      final stillPending = financeNotifier.state.transactions
          .where((t) => t.syncStatus == SyncStatus.pending)
          .toList();
      expect(stillPending.length, equals(pendingList.length));
      expect(syncNotifier.state.pendingCount, equals(pendingList.length));
    });

    test('An exception thrown by the cloud push is swallowed and the queue kept', () async {
      syncNotifier = SyncEngineNotifier(
        pushPending: (_) async => throw Exception('network reset'),
      );

      financeNotifier.addTransaction(
        accountId: testAccountId,
        type: TransactionType.expense,
        amount: 99.0,
        merchant: 'Flaky Network Cafe',
        date: DateTime.now(),
        isOnline: false,
      );

      final pendingList = financeNotifier.state.transactions
          .where((t) => t.syncStatus == SyncStatus.pending)
          .toList();

      syncNotifier.toggleNetwork(true);

      final count = await syncNotifier.flushPendingQueue(
        pendingList,
        (id) => financeNotifier.markTransactionSynced(id),
      );

      expect(count, equals(0));
      expect(syncNotifier.state.isSyncing, isFalse);
      final stillPending = financeNotifier.state.transactions
          .where((t) => t.syncStatus == SyncStatus.pending)
          .toList();
      expect(stillPending.length, equals(pendingList.length));
    });
  });
}
