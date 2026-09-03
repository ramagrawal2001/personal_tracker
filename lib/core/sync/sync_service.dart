import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/finance_repository.dart' show appDatabaseProvider, financeNotifierProvider;
import '../services/supabase_service.dart';
import '../../features/auth/presentation/auth_repository.dart';
import 'cloud_gateway.dart';
import 'outbox_drainer.dart';
import 'outbox_write_through.dart';
import 'remote_apply_sink.dart';
import 'sync_status.dart';

/// Where a remote change gets applied. Phase 2/3 route realtime + pull results
/// through this; Phase 1 just stores the reference.
abstract class RemoteApplySink {
  void applyRemote(String table, Map<String, dynamic> row);
}

/// Owns the sync lifecycle: bind to a user, one-time backfill of the local
/// data into the outbox, and draining the outbox to the cloud on a timer.
///
/// Phase 1 is push-only — no pull, no realtime. Every network await is guarded
/// so a paused free-tier project can never crash the app.
class SyncService {
  final AppDatabase db;
  final CloudGateway gateway;
  final SyncStatusNotifier status;
  final RemoteApplySink sink;

  /// Invoked when [start] is called with a different user than the one the
  /// local DB is bound to (wired to `FinanceNotifier.clearForNewUser`).
  final void Function(String userId)? onUserSwitch;

  late final OutboxDrainer _drainer = OutboxDrainer(db: db, gateway: gateway);

  String? _startedUser;
  Timer? _timer;
  bool _draining = false;

  SyncService({
    required this.db,
    required this.gateway,
    required this.status,
    required this.sink,
    this.onUserSwitch,
  });

  bool get isStarted => _startedUser != null;

  /// Idempotent. Safe no-op when Supabase is uninitialised or there is no
  /// session.
  Future<void> start(String userId) async {
    if (!gateway.isAvailable) return;
    if (_startedUser == userId) return;
    _startedUser = userId;
    try {
      final bound = await _meta('bound_user');
      if (bound != null && bound != userId) {
        try {
          onUserSwitch?.call(userId);
        } catch (e) {
          debugPrint('SyncService.onUserSwitch failed: $e');
        }
        await _wipeForUserSwitch();
      }
      await _setMeta('bound_user', userId);
      await _seedBackfillIfNeeded(userId);
      await _drainLoop();
      _armTimer();
    } catch (e, st) {
      debugPrint('SyncService.start failed: $e\n$st');
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _startedUser = null;
  }

  Future<void> flushNow() => _drainLoop();

  /// After a vault restore rewrites local rows directly: re-enqueue everything.
  Future<void> reseedFromLocal() async {
    try {
      final uid = _startedUser ?? await _meta('bound_user') ?? 'me';
      await db.transaction(() async {
        await _enqueueAllLive(uid, DateTime.now().microsecondsSinceEpoch);
      });
      await _drainLoop();
    } catch (e, st) {
      debugPrint('SyncService.reseedFromLocal failed: $e\n$st');
    }
  }

  // ── lifecycle internals ───────────────────────────────────────────────────

  Future<void> _seedBackfillIfNeeded(String userId) async {
    try {
      final key = 'backfill:$userId';
      if (await _meta(key) != null) return;
      await db.transaction(() async {
        await _enqueueAllLive(userId, DateTime.now().microsecondsSinceEpoch);
      });
      await _setMeta(key, DateTime.now().toIso8601String());
    } catch (e, st) {
      debugPrint('SyncService._seedBackfillIfNeeded failed: $e\n$st');
    }
  }

  Future<void> _enqueueAllLive(String userId, int seqBase) async {
    var i = 0;

    Future<void> addTable(String table, List<String> ids) async {
      for (final id in ids) {
        await enqueueOutboxRow(db, table, id, 'upsert', seq: seqBase + (i++));
      }
    }

    await addTable(
      'accounts',
      (await (db.select(db.accounts)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'categories',
      (await (db.select(db.categories)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'transactions',
      (await (db.select(db.transactions)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'credit_cards',
      (await (db.select(db.creditCards)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'loans',
      (await (db.select(db.loans)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'budgets',
      (await (db.select(db.budgets)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'recurring_payments',
      (await (db.select(db.recurringPayments)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'investments',
      (await (db.select(db.investments)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'goals',
      (await (db.select(db.goals)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await addTable(
      'notes',
      (await (db.select(db.notes)..where((t) => t.isDeleted.equals(false))).get()).map((e) => e.id).toList(),
    );
    await enqueueOutboxRow(db, 'user_settings', userId, 'upsert', seq: seqBase + (i++));
  }

  Future<void> _wipeForUserSwitch() async {
    await db.transaction(() async {
      await db.delete(db.syncOutbox).go();
      await (db.delete(db.syncMeta)
            ..where((m) =>
                m.key.like('watermark:%') |
                m.key.like('bootstrap:%') |
                m.key.like('backfill:%')))
          .go();
    });
  }

  Future<void> _drainLoop() async {
    if (_draining) return;
    _draining = true;
    status.setSyncing(true);
    try {
      var guard = 0;
      while (gateway.isAvailable && guard++ < 64) {
        final res = await _drainer.drainOnce();
        status.update(
          isOnline: true,
          pendingCount: res.remaining,
          deadLetterCount: await _drainer.deadLetterCount(),
          lastSyncTime: DateTime.now(),
          lastError: null,
        );
        if (res.remaining == 0 || res.pushed == 0) break;
      }
      if (!gateway.isAvailable) {
        status.update(isOnline: false);
      }
    } catch (e, st) {
      debugPrint('SyncService._drainLoop failed: $e\n$st');
      status.update(isOnline: false, lastError: e.toString());
    } finally {
      _draining = false;
      status.setSyncing(false);
    }
  }

  void _armTimer() {
    _timer?.cancel();
    _scheduleNext();
  }

  /// Self-rescheduling timer: fast (30s) while the outbox is non-empty, slow
  /// (5min) otherwise. Doubles as a resume probe for the paused-project case.
  void _scheduleNext() {
    _timer?.cancel();
    unawaited(_scheduleNextAsync());
  }

  Future<void> _scheduleNextAsync() async {
    if (_startedUser == null) return;
    int pending;
    try {
      pending = await _drainer.pendingCount();
    } catch (_) {
      pending = 0;
    }
    if (_startedUser == null) return;
    final delay = pending > 0 ? const Duration(seconds: 30) : const Duration(minutes: 5);
    _timer = Timer(delay, () async {
      if (_startedUser == null) return;
      await _drainLoop();
      if (_startedUser != null) _scheduleNext();
    });
  }

  // ── meta helpers ──────────────────────────────────────────────────────────

  Future<String?> _meta(String key) async {
    final r = await (db.select(db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull();
    return r?.value;
  }

  Future<void> _setMeta(String key, String value) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion(key: Value(key), value: Value(value)),
        );
  }
}

/// Production gateway. Overridden with a fake in tests.
final cloudGatewayProvider = Provider<CloudGateway>((ref) => SupabaseCloudGateway());

final syncServiceProvider = Provider<SyncService>((ref) {
  final svc = SyncService(
    db: ref.watch(appDatabaseProvider),
    gateway: ref.watch(cloudGatewayProvider),
    status: ref.watch(syncStatusProvider.notifier),
    sink: RiverpodRemoteApplySink(ref),
    onUserSwitch: (uid) {
      // Also covers a latent bug: plain signIn as a different user never
      // called clearForNewUser before.
      if (SupabaseService.isInitialized) {
        ref.read(financeNotifierProvider.notifier).clearForNewUser(uid);
      }
    },
  );

  ref.listen<AuthState>(
    authNotifierProvider,
    (prev, next) {
      if (next.isAuthenticated && next.user != null) {
        svc.start(next.user!.id);
      } else {
        svc.stop();
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(svc.stop);
  return svc;
});
