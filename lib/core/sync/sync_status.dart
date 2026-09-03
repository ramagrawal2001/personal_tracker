import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the sync layer's health, surfaced in Settings.
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final int pendingCount;
  final int deadLetterCount;
  final DateTime? lastSyncTime;
  final String? lastError;

  const SyncStatus({
    this.isOnline = false,
    this.isSyncing = false,
    this.pendingCount = 0,
    this.deadLetterCount = 0,
    this.lastSyncTime,
    this.lastError,
  });

  SyncStatus copyWith({
    bool? isOnline,
    bool? isSyncing,
    int? pendingCount,
    int? deadLetterCount,
    DateTime? lastSyncTime,
    Object? lastError = _sentinel,
  }) {
    return SyncStatus(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      deadLetterCount: deadLetterCount ?? this.deadLetterCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastError: identical(lastError, _sentinel) ? this.lastError : lastError as String?,
    );
  }

  static const Object _sentinel = Object();
}

class SyncStatusNotifier extends StateNotifier<SyncStatus> {
  SyncStatusNotifier() : super(const SyncStatus());

  void setSyncing(bool value) => state = state.copyWith(isSyncing: value);

  void update({
    bool? isOnline,
    bool? isSyncing,
    int? pendingCount,
    int? deadLetterCount,
    DateTime? lastSyncTime,
    Object? lastError = SyncStatus._sentinel,
  }) {
    state = state.copyWith(
      isOnline: isOnline,
      isSyncing: isSyncing,
      pendingCount: pendingCount,
      deadLetterCount: deadLetterCount,
      lastSyncTime: lastSyncTime,
      lastError: lastError,
    );
  }
}

final syncStatusProvider =
    StateNotifierProvider<SyncStatusNotifier, SyncStatus>((_) => SyncStatusNotifier());
