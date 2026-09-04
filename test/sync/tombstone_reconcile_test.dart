import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/core/sync/sync_status.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_gateway.dart';

/// Bug 1: a local unsynced delete must not outrank a still-alive cloud record
/// forever. `_mergeRemote` restores the row unless the local delete was
/// *confirmed* by the cloud.
class _RecordingSink implements RemoteApplySink {
  final List<({String table, Map<String, dynamic> row})> calls = [];
  @override
  void applyRemote(String table, Map<String, dynamic> row) => calls.add((table: table, row: row));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeCloudGateway gateway;
  late SyncStatusNotifier status;
  late _RecordingSink sink;
  late SyncService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = FakeCloudGateway();
    status = SyncStatusNotifier();
    sink = _RecordingSink();
    svc = SyncService(db: db, gateway: gateway, status: status, sink: sink);
  });

  tearDown(() async {
    await svc.stop();
    status.dispose();
    await gateway.dispose();
    await db.close();
  });

  Future<void> putLocalTombstone(String id, DateTime updatedAt) async {
    final m = AccountModel(
      id: id,
      name: 'Acc $id',
      type: AccountType.savingsAccount,
      openingBalance: 10,
      calculatedBalance: 10,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
      isDeleted: true,
    );
    await db.into(db.accounts).insertOnConflictUpdate(m.toCompanion());
  }

  Map<String, dynamic> aliveRemote(String id, DateTime updatedAt) => AccountModel(
        id: id,
        name: 'Remote $id',
        type: AccountType.savingsAccount,
        openingBalance: 99,
        calculatedBalance: 99,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: updatedAt,
        isDeleted: false,
      ).toCloudJson();

  Future<void> queueDelete(String id, {int attempts = 0, bool deadLettered = false}) async {
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
          entityTable: 'accounts',
          entityId: id,
          op: 'delete',
          seq: DateTime.now().microsecondsSinceEpoch,
          attempts: Value(attempts),
          deadLettered: Value(deadLettered),
        ));
  }

  test('local tombstone (now) + alive older remote + no confirmed delete → RESTORE', () async {
    await putLocalTombstone('a', DateTime.now());
    final outcome = await svc.mergeRemoteForTest('accounts', aliveRemote('a', DateTime(2026, 1, 1)));
    expect(outcome, MergeOutcome.apply, reason: 'the alive cloud row must be restored, not skipped as stale');
    expect(sink.calls.single.table, 'accounts');
  });

  test('a dead-lettered delete outbox row does NOT block the restore', () async {
    await putLocalTombstone('a', DateTime.now());
    await queueDelete('a', attempts: 8, deadLettered: true);
    final outcome = await svc.mergeRemoteForTest('accounts', aliveRemote('a', DateTime(2026, 1, 1)));
    expect(outcome, MergeOutcome.apply);
    expect(sink.calls.single.table, 'accounts');
  });

  test('an exhausted (attempts >= threshold) delete row does NOT block the restore', () async {
    await putLocalTombstone('a', DateTime.now());
    await queueDelete('a', attempts: 6);
    final outcome = await svc.mergeRemoteForTest('accounts', aliveRemote('a', DateTime(2026, 1, 1)));
    expect(outcome, MergeOutcome.apply);
  });

  test('a FRESH pending delete still defers (skipPending) — correct', () async {
    await putLocalTombstone('a', DateTime.now());
    await queueDelete('a'); // attempts 0, not dead
    final outcome = await svc.mergeRemoteForTest('accounts', aliveRemote('a', DateTime(2026, 1, 1)));
    expect(outcome, MergeOutcome.skipPending);
    expect(sink.calls, isEmpty);
  });

  test('a CONFIRMED delete newer than the remote row still wins (skipStale)', () async {
    await putLocalTombstone('a', DateTime(2026, 8, 1));
    await db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaCompanion(
          key: const Value('deleted:accounts:a'),
          value: Value(DateTime(2026, 8, 1).toUtc().toIso8601String()),
        ));
    final outcome = await svc.mergeRemoteForTest('accounts', aliveRemote('a', DateTime(2026, 6, 1)));
    expect(outcome, MergeOutcome.skipStale);
    expect(sink.calls, isEmpty);
  });

  test('a remote re-creation newer than a confirmed delete resurrects the row', () async {
    await putLocalTombstone('a', DateTime(2026, 8, 1));
    await db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaCompanion(
          key: const Value('deleted:accounts:a'),
          value: Value(DateTime(2026, 8, 1).toUtc().toIso8601String()),
        ));
    final outcome = await svc.mergeRemoteForTest('accounts', aliveRemote('a', DateTime(2026, 12, 1)));
    expect(outcome, MergeOutcome.apply);
    // stale marker cleared so future edits merge normally
    final marker = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('deleted:accounts:a')))
        .getSingleOrNull();
    expect(marker, isNull);
  });

  test('drainer records a confirmed-delete marker after a successful delete push', () async {
    final m = AccountModel(
      id: 'z',
      name: 'Z',
      type: AccountType.savingsAccount,
      openingBalance: 1,
      calculatedBalance: 1,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      isDeleted: true,
    );
    await db.into(db.accounts).insertOnConflictUpdate(m.toCompanion());
    await queueDelete('z');

    await svc.flushNow();

    final marker = await (db.select(db.syncMeta)
          ..where((mm) => mm.key.equals('deleted:accounts:z')))
        .getSingleOrNull();
    expect(marker, isNotNull, reason: 'a successful delete push must leave a confirmed-delete marker');
    expect(gateway.row('accounts', 'z')!['is_deleted'], true);
  });
}
