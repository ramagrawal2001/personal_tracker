import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/finance_repository.dart' show appDatabaseProvider, financeNotifierProvider;
import '../services/supabase_service.dart';
import '../../features/auth/presentation/auth_repository.dart';
import 'cloud_gateway.dart';
import 'cloud_mappers.dart' show kSyncedTables;
import 'outbox_drainer.dart';
import 'outbox_write_through.dart';
import 'remote_apply_sink.dart';
import 'sync_status.dart';

/// Where a remote change gets applied. Pull results and realtime events are
/// routed through this to the live Riverpod notifiers.
abstract class RemoteApplySink {
  void applyRemote(String table, Map<String, dynamic> row);
}

/// Outcome of a single LWW merge decision. Exposed for tests.
enum MergeOutcome {
  /// Remote row applied as an upsert.
  apply,

  /// Remote tombstone applied (row removed / soft-deleted locally).
  applyDelete,

  /// Remote row ignored — a local row is strictly newer.
  skipStale,

  /// Remote row deferred — a local pending outbox row wins for now.
  skipPending,
}

/// Tables the pull/merge pass walks: every synced entity plus `user_settings`.
const List<String> _pullTables = <String>[...kSyncedTables, 'user_settings'];

const int _pullPageSize = 500;

/// Owns the sync lifecycle: bind to a user, one-time backfill of local data
/// into the outbox, pull + LWW-merge the cloud state, drain the outbox, and
/// keep both sides converged via a realtime subscription + a fallback timer.
///
/// Every network await is guarded so a paused free-tier project can never
/// crash the app — failures degrade to "offline" and retry later.
class SyncService {
  final AppDatabase db;
  final CloudGateway gateway;
  final SyncStatusNotifier status;
  final RemoteApplySink sink;

  /// Invoked when [start] is called with a different user than the one the
  /// local DB is bound to (wired to `FinanceNotifier.clearForNewUser`).
  final void Function(String userId)? onUserSwitch;

  late final OutboxDrainer _drainer = OutboxDrainer(
    db: db,
    gateway: gateway,
    onPushed: _recordPush,
  );

  String? _startedUser;
  Timer? _timer;
  bool _draining = false;
  bool _pulling = false;
  StreamSubscription<RemoteChange>? _rtSub;

  /// "table:id" -> server updatedAt of a row we just pushed. Used to drop the
  /// realtime echo of our own writes. Entries older than 2 min are evicted.
  final Map<String, DateTime> _recentPushes = {};

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

      final firstRun = !(await _bootstrapDone(userId));
      await _pullAll(initial: firstRun);
      await _setMeta('bootstrap:$userId', 'true');

      await _drainLoop();

      _subscribeRealtime(userId);
      _armTimer();
    } catch (e, st) {
      debugPrint('SyncService.start failed: $e\n$st');
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _startedUser = null;
    final sub = _rtSub;
    _rtSub = null;
    try {
      await sub?.cancel();
      await gateway.unsubscribe();
    } catch (e) {
      debugPrint('SyncService.stop: unsubscribe failed: $e');
    }
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

  // ── pull + merge ──────────────────────────────────────────────────────────

  Future<void> _pullAll({required bool initial}) async {
    if (_pulling || !gateway.isAvailable) return;
    _pulling = true;
    try {
      for (final table in _pullTables) {
        await _pullTable(table, initial: initial);
      }
      status.update(isOnline: true, lastSyncTime: DateTime.now(), lastError: null);
    } on SyncTransientError catch (e) {
      status.update(isOnline: false, lastError: e.toString());
    } catch (e, st) {
      debugPrint('SyncService._pullAll failed: $e\n$st');
      status.update(lastError: e.toString());
    } finally {
      _pulling = false;
    }
  }

  Future<void> _pullTable(String table, {required bool initial}) async {
    final since = initial ? null : _parseTs(await _meta('watermark:$table'));
    var offset = 0;
    DateTime? maxSeen = since;

    while (true) {
      final page = await gateway.pull(table, since: since, offset: offset, limit: _pullPageSize);
      if (page.isEmpty) break;

      await db.transaction(() async {
        for (final row in page) {
          await _mergeRemote(table, row);
          final ts = _parseTs(row['updated_at'] as String?);
          if (ts != null && (maxSeen == null || ts.isAfter(maxSeen!))) maxSeen = ts;
        }
      });

      if (maxSeen != null) {
        await _setMeta('watermark:$table', maxSeen!.toUtc().toIso8601String());
      }
      if (page.length < _pullPageSize) break;
      offset += _pullPageSize;
    }
  }

  /// LWW merge decision for a single remote row. Visible so tests can assert the
  /// decision table without a live gateway.
  @visibleForTesting
  Future<MergeOutcome> mergeRemoteForTest(String table, Map<String, dynamic> row) =>
      _mergeRemote(table, row);

  Future<MergeOutcome> _mergeRemote(String table, Map<String, dynamic> row) async {
    if (table == 'user_settings') return _mergeRemoteSettings(row);

    final id = row['id'] as String?;
    if (id == null) return MergeOutcome.skipStale;

    final remoteTs = _parseTs(row['updated_at'] as String?);
    final deleted = row['is_deleted'] == true;

    // A local pending change wins for now — our queued push + its realtime echo
    // will reconcile.
    if (await _outboxHas(table, id)) return MergeOutcome.skipPending;

    final localTs = await _localUpdatedAt(table, id);
    if (localTs != null && remoteTs != null && remoteTs.isBefore(localTs)) {
      return MergeOutcome.skipStale;
    }

    sink.applyRemote(table, row);
    return deleted ? MergeOutcome.applyDelete : MergeOutcome.apply;
  }

  Future<MergeOutcome> _mergeRemoteSettings(Map<String, dynamic> row) async {
    final remoteTs = _parseTs(row['updated_at'] as String?);
    final localTs = _parseTs(await _meta('settings_updated_at'));
    if (remoteTs != null && localTs != null && !remoteTs.isAfter(localTs)) {
      return MergeOutcome.skipStale;
    }
    sink.applyRemote('user_settings', row);
    if (remoteTs != null) {
      await _setMeta('settings_updated_at', remoteTs.toUtc().toIso8601String());
    }
    return MergeOutcome.apply;
  }

  Future<bool> _outboxHas(String table, String id) async {
    final r = await (db.select(db.syncOutbox)
          ..where((o) => o.entityTable.equals(table) & o.entityId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return r != null;
  }

  Future<DateTime?> _localUpdatedAt(String table, String id) async {
    switch (table) {
      case 'accounts':
        return (await (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'categories':
        return (await (db.select(db.categories)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'transactions':
        return (await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'credit_cards':
        return (await (db.select(db.creditCards)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'loans':
        return (await (db.select(db.loans)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'budgets':
        return (await (db.select(db.budgets)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'recurring_payments':
        return (await (db.select(db.recurringPayments)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'investments':
        return (await (db.select(db.investments)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'goals':
        return (await (db.select(db.goals)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'notes':
        return (await (db.select(db.notes)..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      default:
        return null;
    }
  }

  // ── realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime(String userId) {
    try {
      _rtSub?.cancel();
      _rtSub = gateway
          .subscribe(userId, _pullTables)
          .listen(_onRemoteChange, onError: (Object e) {
        debugPrint('SyncService realtime stream error: $e');
        status.update(isOnline: false);
      });
    } catch (e, st) {
      debugPrint('SyncService._subscribeRealtime failed: $e\n$st');
    }
  }

  Future<void> _onRemoteChange(RemoteChange c) async {
    try {
      final key = '${c.table}:${c.row['id'] ?? c.row['user_id'] ?? 'me'}';
      final pushed = _recentPushes[key];
      if (pushed != null && !c.updatedAt.isAfter(pushed.add(const Duration(seconds: 1)))) {
        return; // echo of our own write
      }
      _evictStalePushes();
      await db.transaction(() => _mergeRemote(c.table, c.row));
      status.update(isOnline: true, lastSyncTime: DateTime.now());
    } catch (e, st) {
      debugPrint('SyncService._onRemoteChange failed: $e\n$st');
    }
  }

  void _recordPush(String table, String entityId, DateTime serverTs) {
    _recentPushes['$table:$entityId'] = serverTs;
  }

  void _evictStalePushes() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    _recentPushes.removeWhere((_, ts) => ts.isBefore(cutoff));
  }

  // ── lifecycle internals ───────────────────────────────────────────────────

  Future<bool> _bootstrapDone(String userId) async => (await _meta('bootstrap:$userId')) == 'true';

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
  /// (5min) otherwise. Doubles as a resume/reconnect probe — each tick drains
  /// the outbox and pulls any deltas we may have missed while disconnected.
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
      if (_startedUser != null && gateway.isAvailable) {
        await _pullAll(initial: false);
        if (_rtSub == null) _subscribeRealtime(_startedUser!);
      }
      if (_startedUser != null) _scheduleNext();
    });
  }

  // ── meta helpers ──────────────────────────────────────────────────────────

  static DateTime? _parseTs(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

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
