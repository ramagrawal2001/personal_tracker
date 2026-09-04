import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/core/sync/sync_status.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_gateway.dart';

class _RecordingSink implements RemoteApplySink {
  final List<String> tables = [];
  @override
  void applyRemote(String table, Map<String, dynamic> row) => tables.add(table);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeCloudGateway gateway;
  late SyncStatusNotifier status;
  late _RecordingSink sink;
  late SyncService svc;
  final switched = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = FakeCloudGateway();
    status = SyncStatusNotifier();
    sink = _RecordingSink();
    switched.clear();
    svc = SyncService(
      db: db,
      gateway: gateway,
      status: status,
      sink: sink,
      onUserSwitch: switched.add,
    );
  });

  tearDown(() async {
    await svc.stop();
    status.dispose();
    await gateway.dispose();
    await db.close();
  });

  Future<void> seedAccount(String id) async {
    final m = AccountModel(
      id: id,
      name: 'Acc $id',
      type: AccountType.savingsAccount,
      openingBalance: 10,
      calculatedBalance: 10,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await db.into(db.accounts).insertOnConflictUpdate(m.toCompanion());
  }

  Future<String?> meta(String key) async {
    final r = await (db.select(db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull();
    return r?.value;
  }

  test('start() backfills every live local row + user_settings and drains them', () async {
    await seedAccount('a1');
    await seedAccount('a2');

    await svc.start('user-1');

    expect(gateway.rowCount('accounts'), 2);
    expect(gateway.rowCount('user_settings'), 1);
    expect(gateway.row('user_settings', 'user-1'), isNotNull);
    expect(await meta('bound_user'), 'user-1');
    expect(await meta('backfill:user-1'), isNotNull);

    final pending = await (db.select(db.syncOutbox)..where((r) => r.deadLettered.equals(false))).get();
    expect(pending, isEmpty);
    expect(status.state.pendingCount, 0);
  });

  test('start() is idempotent for the same user', () async {
    await seedAccount('a1');
    await svc.start('user-1');
    final firstCount = gateway.upsertCount;

    await seedAccount('a2');
    await svc.start('user-1'); // no-op: already started

    expect(gateway.upsertCount, firstCount);
  });

  test('start() is a safe no-op when the gateway is unavailable', () async {
    await seedAccount('a1');
    gateway.available = false;

    await svc.start('user-1');

    expect(gateway.upsertCount, 0);
    expect(svc.isStarted, isFalse);
    expect(await meta('bound_user'), isNull);
  });

  test('starting as a different user triggers onUserSwitch and wipes the outbox', () async {
    // Pretend the DB is already bound to another user with queued work.
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion(key: const Value('bound_user'), value: const Value('old-user')),
        );
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion(key: const Value('backfill:old-user'), value: const Value('x')),
        );
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
          entityTable: 'accounts',
          entityId: 'stale',
          op: 'upsert',
          seq: 1,
        ));

    await seedAccount('a1');
    await svc.start('new-user');

    expect(switched, ['new-user']);
    expect(await meta('bound_user'), 'new-user');
    expect(await meta('backfill:old-user'), isNull); // wiped
    expect(await meta('backfill:new-user'), isNotNull); // fresh backfill ran
    // The stale row was wiped; only the fresh backfill's rows were drained.
    expect(gateway.row('accounts', 'stale'), isNull);
    expect(gateway.row('accounts', 'a1'), isNotNull);
  });

  test('forceFullResync() re-applies a remote row a stale watermark was hiding', () async {
    await svc.start('user-1'); // empty local + empty remote; sets bound_user/bootstrap
    sink.tables.clear();

    // A row exists in the cloud that this device never applied locally (e.g.
    // edited directly server-side) — its updated_at predates a watermark this
    // device already advanced past, so an ordinary delta pull would never
    // see it again.
    gateway.seed('accounts', {'id': 'ghost', 'updated_at': '2026-01-01T00:00:00.000Z', 'is_deleted': false});
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion(
            key: const Value('watermark:accounts'),
            value: const Value('2026-06-01T00:00:00.000Z'),
          ),
        );

    await svc.forceFullResync();

    expect(sink.tables, contains('accounts'));
    expect(await meta('bootstrap:user-1'), 'true');
  });

  test('flushNow() drains rows queued after start', () async {
    await svc.start('user-1');
    gateway.store.clear();

    await seedAccount('later');
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
          entityTable: 'accounts',
          entityId: 'later',
          op: 'upsert',
          seq: DateTime.now().microsecondsSinceEpoch,
        ));

    await svc.flushNow();
    expect(gateway.row('accounts', 'later'), isNotNull);
  });
}
