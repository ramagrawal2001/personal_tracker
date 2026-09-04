import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/sync/cloud_gateway.dart';
import 'package:aspyric/core/sync/cloud_mappers.dart';
import 'package:aspyric/core/sync/sync_service.dart';
import 'package:aspyric/core/sync/sync_status.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_gateway.dart';

/// Bug 3: the initial (bootstrap) pull for a table must be all-or-nothing. A
/// failure mid-pull must leave the per-table watermark unset so the next
/// `start()` re-fetches the whole table.

// Must match SyncService's private `_pullPageSize`.
const int _pageSize = 500;

class _FlakyGateway extends FakeCloudGateway {
  int failuresRemaining;
  final List<Map<String, dynamic>> page1;
  final List<Map<String, dynamic>> page2;

  _FlakyGateway({
    required this.failuresRemaining,
    required this.page1,
    required this.page2,
  });

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    DateTime? since,
    int limit = 500,
    int offset = 0,
  }) async {
    if (table != 'goals') return const [];
    if (offset == 0) return page1;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw SyncTransientError('flaky page 2');
    }
    if (offset == page1.length) return page2;
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FlakyGateway gateway;
  late SyncStatusNotifier status;
  late _CountingSink sink;

  final page1 = List.generate(
    _pageSize,
    (i) => GoalModel(
      id: 'g$i',
      name: 'G$i',
      targetAmount: 1,
      currentSavedAmount: 0,
      updatedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
    ).toCloudJson(),
  );
  final page2 = [
    GoalModel(
      id: 'g-late',
      name: 'Late',
      targetAmount: 2,
      currentSavedAmount: 0,
      updatedAt: DateTime.utc(2026, 6, 1),
    ).toCloudJson(),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = _FlakyGateway(failuresRemaining: 1, page1: page1, page2: page2);
    status = SyncStatusNotifier();
    sink = _CountingSink();
  });

  tearDown(() async {
    status.dispose();
    await gateway.dispose();
    await db.close();
  });

  Future<String?> meta(String key) async =>
      (await (db.select(db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull())?.value;

  test('a failure on page 2 of the initial pull leaves the watermark unset and applies nothing', () async {
    final svc = SyncService(db: db, gateway: gateway, status: status, sink: sink);
    await svc.start('u1');
    await svc.stop();

    expect(await meta('watermark:goals'), isNull, reason: 'watermark must not advance on a partial initial pull');
    expect(await meta('bootstrap:u1'), isNull, reason: 'bootstrap not marked done after a failed initial pull');
    expect(sink.countFor('goals'), 0, reason: 'initial pull is atomic — no page-1 rows applied when page 2 fails');
  });

  test('the next start() re-pulls the whole table once page 2 succeeds', () async {
    final svc1 = SyncService(db: db, gateway: gateway, status: status, sink: sink);
    await svc1.start('u1'); // fails on page 2
    await svc1.stop();
    expect(sink.countFor('goals'), 0);

    // failuresRemaining is now 0 — page 2 will succeed this time.
    final svc2 = SyncService(db: db, gateway: gateway, status: status, sink: sink);
    await svc2.start('u1');
    await svc2.stop();

    expect(sink.countFor('goals'), _pageSize + 1, reason: 'all page-1 rows + page-2 row applied on retry');
    expect(await meta('watermark:goals'), isNotNull);
    expect(await meta('bootstrap:u1'), isNotNull);
  });
}

class _CountingSink implements RemoteApplySink {
  final Map<String, int> _counts = {};
  @override
  void applyRemote(String table, Map<String, dynamic> row) =>
      _counts[table] = (_counts[table] ?? 0) + 1;
  int countFor(String table) => _counts[table] ?? 0;
}
