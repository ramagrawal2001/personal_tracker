import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/sync/cloud_gateway.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/core/sync/sync_status.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_gateway.dart';

class _RecordingSink implements RemoteApplySink {
  final List<({String table, String? id, bool deleted})> calls = [];
  @override
  void applyRemote(String table, Map<String, dynamic> row) => calls.add((
        table: table,
        id: row['id'] as String?,
        deleted: row['is_deleted'] == true,
      ));
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

  Map<String, dynamic> goalRow(String id, DateTime updatedAt, {bool deleted = false}) => GoalModel(
        id: id,
        name: 'Goal $id',
        targetAmount: 10,
        currentSavedAmount: 1,
        updatedAt: updatedAt,
        isDeleted: deleted,
      ).toCloudJson();

  test('a realtime upsert is merged into the local store', () async {
    await svc.start('u1');
    sink.calls.clear();

    final ts = DateTime.utc(2026, 5, 5);
    gateway.pushRemote(RemoteChange(
      table: 'goals',
      op: 'upsert',
      row: goalRow('g1', ts),
      updatedAt: ts.toLocal(),
    ));
    await pumpEventQueue();

    expect(sink.calls.where((c) => c.table == 'goals' && c.id == 'g1'), hasLength(1));
    expect(sink.calls.single.deleted, isFalse);
  });

  test('a realtime tombstone routes as a delete', () async {
    await svc.start('u1');
    sink.calls.clear();

    final ts = DateTime.utc(2026, 6, 6);
    gateway.pushRemote(RemoteChange(
      table: 'goals',
      op: 'delete',
      row: goalRow('g2', ts, deleted: true),
      updatedAt: ts.toLocal(),
    ));
    await pumpEventQueue();

    expect(sink.calls.single.id, 'g2');
    expect(sink.calls.single.deleted, isTrue);
  });

  test('the echo of our own push is dropped', () async {
    await svc.start('u1');

    // Simulate a local write we just pushed: seed the account + outbox row,
    // flush it (the fake gateway fires onPushed -> _recentPushes), then a
    // realtime event carrying the same server timestamp must be ignored.
    final acc = AccountModel(
      id: 'e1',
      name: 'Echo',
      type: AccountType.savingsAccount,
      openingBalance: 1,
      calculatedBalance: 1,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await db.into(db.accounts).insertOnConflictUpdate(acc.toCompanion());
    final fixedTs = DateTime.utc(2026, 7, 7, 12);
    gateway.clock = () => fixedTs;
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
          entityTable: 'accounts',
          entityId: 'e1',
          op: 'upsert',
          seq: DateTime.now().microsecondsSinceEpoch,
        ));
    await svc.flushNow();
    sink.calls.clear();

    // Echo: same timestamp as the push we just made.
    gateway.pushRemote(RemoteChange(
      table: 'accounts',
      op: 'upsert',
      row: {'id': 'e1', 'updated_at': fixedTs.toIso8601String(), 'is_deleted': false},
      updatedAt: fixedTs.toLocal(),
    ));
    await pumpEventQueue();
    expect(sink.calls, isEmpty, reason: 'own echo suppressed');

    // A genuinely newer change for the same row is still applied.
    final newerTs = fixedTs.add(const Duration(minutes: 5));
    gateway.pushRemote(RemoteChange(
      table: 'accounts',
      op: 'upsert',
      row: {'id': 'e1', 'updated_at': newerTs.toIso8601String(), 'is_deleted': false},
      updatedAt: newerTs.toLocal(),
    ));
    await pumpEventQueue();
    expect(sink.calls.where((c) => c.id == 'e1'), hasLength(1));
  });
}
