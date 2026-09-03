import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/models.dart';
import 'edge_function_service.dart';

class SyncEngineState {
  final bool isOnline;
  final int pendingCount;
  final bool isSyncing;
  final String? lastSyncTime;

  SyncEngineState({
    this.isOnline = true,
    this.pendingCount = 0,
    this.isSyncing = false,
    this.lastSyncTime,
  });

  SyncEngineState copyWith({
    bool? isOnline,
    int? pendingCount,
    bool? isSyncing,
    String? lastSyncTime,
  }) {
    return SyncEngineState(
      isOnline: isOnline ?? this.isOnline,
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

class SyncEngineNotifier extends StateNotifier<SyncEngineState> {
  /// Pushes pending transactions to the cloud and returns the set of ids the
  /// server confirmed. Injectable so tests can exercise the queue without a
  /// live backend; defaults to the real edge-function call.
  final Future<Set<String>> Function(List<TransactionModel>) _pushPending;

  SyncEngineNotifier({
    Future<Set<String>> Function(List<TransactionModel>)? pushPending,
  })  : _pushPending = pushPending ?? EdgeFunctionService.pushPendingTransactions,
        super(SyncEngineState());

  void toggleNetwork(bool online) {
    state = state.copyWith(isOnline: online);
    debugPrint('🌐 Network status changed: ${online ? "ONLINE" : "OFFLINE"}');
  }

  /// Flushes pending offline transactions when the network is available.
  ///
  /// A transaction is marked synced **only** once the server confirms it was
  /// persisted. If the push fails (offline, auth error, server error) nothing
  /// is marked and the items stay queued for the next retry — previously the
  /// queue drained itself even when the edge function returned an error.
  Future<int> flushPendingQueue(
    List<TransactionModel> pendingList,
    void Function(String id) markAsSynced,
  ) async {
    if (!state.isOnline || pendingList.isEmpty) {
      state = state.copyWith(pendingCount: pendingList.length);
      return 0;
    }

    state = state.copyWith(isSyncing: true);

    Set<String> syncedIds;
    try {
      syncedIds = await _pushPending(pendingList);
    } catch (e) {
      debugPrint('flushPendingQueue: sync failed, keeping queue: $e');
      syncedIds = const {};
    }

    for (final id in syncedIds) {
      markAsSynced(id);
    }

    state = state.copyWith(
      isSyncing: false,
      pendingCount: pendingList.length - syncedIds.length,
      lastSyncTime: syncedIds.isNotEmpty ? 'Just now' : state.lastSyncTime,
    );

    return syncedIds.length;
  }
}

final syncEngineProvider = StateNotifierProvider<SyncEngineNotifier, SyncEngineState>((ref) {
  return SyncEngineNotifier();
});
