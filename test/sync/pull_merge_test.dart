import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/core/sync/sync_status.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_gateway.dart';

class _RecordingSink implements RemoteApplySink {
  final List<({String table, String? id})> calls = [];
  @override
  void applyRemote(String table, Map<String, dynamic> row) =>
      calls.add((table: table, id: row['id'] as String?));

  int countFor(String table) => calls.where((c) => c.table == table).length;
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

  Map<String, dynamic> remoteGoal(String id, DateTime updatedAt) => GoalModel(
        id: id,
        name: 'Goal $id',
        targetAmount: 1000,
        currentSavedAmount: 100,
        updatedAt: updatedAt,
      ).toCloudJson();

  test('initial start pulls every remote row and advances watermarks', () async {
    gateway.seed('goals', remoteGoal('g1', DateTime.utc(2026, 2, 1)));
    gateway.seed('goals', remoteGoal('g2', DateTime.utc(2026, 3, 1)));

    await svc.start('u1');

    expect(sink.countFor('goals'), 2);
    final wm = await (db.select(db.syncMeta)..where((m) => m.key.equals('watermark:goals'))).getSingleOrNull();
    expect(wm, isNotNull);
    expect(DateTime.parse(wm!.value).toUtc(), DateTime.utc(2026, 3, 1));
    expect(await (db.select(db.syncMeta)..where((m) => m.key.equals('bootstrap:u1'))).getSingleOrNull(), isNotNull);
  });

  test('a second start is a delta pull — unchanged rows are not re-applied', () async {
    gateway.seed('goals', remoteGoal('g1', DateTime.utc(2026, 2, 1)));
    await svc.start('u1');
    expect(sink.countFor('goals'), 1);

    sink.calls.clear();
    await svc.stop();

    // Fresh service instance, same DB (simulates app relaunch).
    final svc2 = SyncService(db: db, gateway: gateway, status: status, sink: sink);
    await svc2.start('u1');
    expect(sink.countFor('goals'), 0, reason: 'no rows newer than the stored watermark');

    gateway.seed('goals', remoteGoal('g9', DateTime.utc(2026, 12, 1)));
    await svc2.flushNow();
    // flushNow only drains; force a delta pull the way the timer would.
    await svc2.stop();
    final svc3 = SyncService(db: db, gateway: gateway, status: status, sink: sink);
    await svc3.start('u1');
    expect(sink.countFor('goals'), 1);
    await svc3.stop();
  });

  test('a remote row older than the local row is skipped during pull', () async {
    // Local goal is newer than what the cloud offers.
    final local = GoalModel(
      id: 'g1',
      name: 'Local',
      targetAmount: 1,
      currentSavedAmount: 0,
      updatedAt: DateTime(2026, 9, 9),
    );
    await db.into(db.goals).insertOnConflictUpdate(local.toCompanion());
    gateway.seed('goals', remoteGoal('g1', DateTime.utc(2026, 1, 1)));

    await svc.start('u1');

    expect(sink.countFor('goals'), 0);
  });

  test('start is a no-op offline and leaves no watermark', () async {
    gateway.seed('goals', remoteGoal('g1', DateTime.utc(2026, 2, 1)));
    gateway.available = false;

    await svc.start('u1');

    expect(sink.calls, isEmpty);
    expect(await (db.select(db.syncMeta)..where((m) => m.key.equals('watermark:goals'))).getSingleOrNull(), isNull);
  });

  test('backfill + pull interleave: local rows push, remote-only rows pull', () async {
    final acc = AccountModel(
      id: 'a-local',
      name: 'Local acc',
      type: AccountType.savingsAccount,
      openingBalance: 5,
      calculatedBalance: 5,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await db.into(db.accounts).insertOnConflictUpdate(acc.toCompanion());
    gateway.seed('goals', remoteGoal('g-remote', DateTime.utc(2026, 4, 1)));

    await svc.start('u1');

    expect(gateway.row('accounts', 'a-local'), isNotNull, reason: 'local row backfilled up');
    expect(sink.countFor('goals'), 1, reason: 'remote-only row pulled down');
  });
}
