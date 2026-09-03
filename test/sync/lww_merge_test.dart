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

  Future<void> putLocalAccount(String id, DateTime updatedAt, {bool isDeleted = false}) async {
    final m = AccountModel(
      id: id,
      name: 'Acc $id',
      type: AccountType.savingsAccount,
      openingBalance: 10,
      calculatedBalance: 10,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
    await db.into(db.accounts).insertOnConflictUpdate(m.toCompanion());
  }

  Map<String, dynamic> remoteAccount(String id, DateTime updatedAt, {bool isDeleted = false}) {
    final m = AccountModel(
      id: id,
      name: 'Remote $id',
      type: AccountType.savingsAccount,
      openingBalance: 99,
      calculatedBalance: 99,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
    return m.toCloudJson();
  }

  Future<void> queueOutbox(String table, String id) async {
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
          entityTable: table,
          entityId: id,
          op: 'upsert',
          seq: DateTime.now().microsecondsSinceEpoch,
        ));
  }

  test('newer remote applies over an older local row', () async {
    await putLocalAccount('a', DateTime(2026, 1, 1));
    final outcome = await svc.mergeRemoteForTest('accounts', remoteAccount('a', DateTime(2026, 6, 1)));
    expect(outcome, MergeOutcome.apply);
    expect(sink.calls.single.table, 'accounts');
  });

  test('older remote is skipped as stale', () async {
    await putLocalAccount('a', DateTime(2026, 6, 1));
    final outcome = await svc.mergeRemoteForTest('accounts', remoteAccount('a', DateTime(2026, 1, 1)));
    expect(outcome, MergeOutcome.skipStale);
    expect(sink.calls, isEmpty);
  });

  test('equal timestamp still applies (>= rule)', () async {
    final ts = DateTime(2026, 3, 3);
    await putLocalAccount('a', ts);
    final outcome = await svc.mergeRemoteForTest('accounts', remoteAccount('a', ts));
    expect(outcome, MergeOutcome.apply);
  });

  test('a pending local outbox row defers any remote change', () async {
    await putLocalAccount('a', DateTime(2026, 1, 1));
    await queueOutbox('accounts', 'a');
    final outcome = await svc.mergeRemoteForTest('accounts', remoteAccount('a', DateTime(2026, 9, 9)));
    expect(outcome, MergeOutcome.skipPending);
    expect(sink.calls, isEmpty);
  });

  test('remote row with no local counterpart applies', () async {
    final outcome = await svc.mergeRemoteForTest('accounts', remoteAccount('brand-new', DateTime(2026, 2, 2)));
    expect(outcome, MergeOutcome.apply);
  });

  test('newer remote tombstone applies as a delete', () async {
    await putLocalAccount('a', DateTime(2026, 1, 1));
    final outcome = await svc.mergeRemoteForTest(
      'accounts',
      remoteAccount('a', DateTime(2026, 5, 5), isDeleted: true),
    );
    expect(outcome, MergeOutcome.applyDelete);
  });

  test('resurrection guard: an older edit loses to a newer delete', () async {
    // Local row was deleted at T2; a stale device pushes an edit stamped T1.
    await putLocalAccount('a', DateTime(2026, 7, 1), isDeleted: true);
    final outcome = await svc.mergeRemoteForTest('accounts', remoteAccount('a', DateTime(2026, 6, 1)));
    expect(outcome, MergeOutcome.skipStale);
    expect(sink.calls, isEmpty);
  });

  test('settings: newer remote applies and advances the watermark', () async {
    final row = settingsToCloudJson(
      'u1',
      emergencyBuffer: 5000,
      currencySymbol: r'$',
      isRoundUpEnabled: true,
      isAutoBackupEnabled: false,
      updatedAt: DateTime(2026, 8, 1),
    );
    final outcome = await svc.mergeRemoteForTest('user_settings', row);
    expect(outcome, MergeOutcome.apply);
    expect(sink.calls.single.table, 'user_settings');
    final wm = await (db.select(db.syncMeta)..where((m) => m.key.equals('settings_updated_at'))).getSingleOrNull();
    expect(wm, isNotNull);
  });

  test('settings: not-newer remote is skipped', () async {
    await db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaCompanion(
          key: const Value('settings_updated_at'),
          value: Value(DateTime(2026, 8, 1).toUtc().toIso8601String()),
        ));
    final row = settingsToCloudJson(
      'u1',
      emergencyBuffer: 5000,
      currencySymbol: r'$',
      isRoundUpEnabled: true,
      isAutoBackupEnabled: false,
      updatedAt: DateTime(2026, 8, 1),
    );
    final outcome = await svc.mergeRemoteForTest('user_settings', row);
    expect(outcome, MergeOutcome.skipStale);
    expect(sink.calls, isEmpty);
  });
}
