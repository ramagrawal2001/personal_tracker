import 'package:aspyric/core/constants/app_constants.dart';
import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_mappers.dart';
import 'package:aspyric/core/sync/outbox_drainer.dart';
import 'package:aspyric/core/sync/outbox_write_through.dart';
import 'package:aspyric/domain/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cloud_gateway.dart';

void main() {
  late AppDatabase db;
  late FakeCloudGateway gateway;
  late OutboxDrainer drainer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = FakeCloudGateway();
    drainer = OutboxDrainer(db: db, gateway: gateway);
  });

  tearDown(() async {
    await gateway.dispose();
    await db.close();
  });

  Future<AccountModel> insertAccount(String id) async {
    final m = AccountModel(
      id: id,
      name: 'Acc $id',
      type: AccountType.savingsAccount,
      openingBalance: 100,
      calculatedBalance: 100,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await db.into(db.accounts).insertOnConflictUpdate(m.toCompanion());
    return m;
  }

  test('drains a queued upsert, pushes current row, deletes the outbox row', () async {
    await insertAccount('a1');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');

    final res = await drainer.drainOnce();

    expect(res.pushed, 1);
    expect(res.remaining, 0);
    expect(gateway.rowCount('accounts'), 1);
    expect(gateway.row('accounts', 'a1')!['name'], 'Acc a1');
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });

  test('two edits to one id coalesce to a single row and one push', () async {
    await insertAccount('a1');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');

    expect((await db.select(db.syncOutbox).get()).length, 1);

    final res = await drainer.drainOnce();
    expect(res.pushed, 1);
    expect(gateway.upsertCount, 1);
  });

  test('FIFO by seq', () async {
    await insertAccount('a1');
    await insertAccount('a2');
    await enqueueOutboxRow(db, 'accounts', 'a2', 'upsert', seq: 200);
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert', seq: 100);

    await drainer.drainOnce();
    expect(gateway.upsertedIds, ['a1', 'a2']);
  });

  test('transient error bumps attempts and pushes nextRetryAt into the future', () async {
    await insertAccount('a1');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');
    gateway.throwTransient = true;

    final before = DateTime.now();
    final res = await drainer.drainOnce();

    expect(res.pushed, 0);
    expect(res.failed, 1);
    final row = (await db.select(db.syncOutbox).get()).single;
    expect(row.attempts, 1);
    expect(row.deadLettered, isFalse);
    expect(row.nextRetryAt.isAfter(before.add(const Duration(seconds: 1))), isTrue);
    expect(row.lastError, isNotNull);
  });

  test('growing backoff across repeated transient failures', () async {
    await insertAccount('a1');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');
    gateway.throwTransient = true;

    Future<Duration> drainAndReadDelay() async {
      final base = DateTime.now();
      await (db.update(db.syncOutbox)).write(
        SyncOutboxCompanion(nextRetryAt: Value(base.subtract(const Duration(hours: 1)))),
      );
      await drainer.drainOnce();
      return (await db.select(db.syncOutbox).get()).single.nextRetryAt.difference(base);
    }

    final d1 = await drainAndReadDelay(); // attempt 1 -> ~4s + jitter
    await drainAndReadDelay(); // attempt 2
    await drainAndReadDelay(); // attempt 3
    final d4 = await drainAndReadDelay(); // attempt 4 -> ~32s + jitter
    expect(d4 > d1, isTrue);
  });

  test('8 transient attempts dead-letters the row; it is retained and skipped', () async {
    await insertAccount('a1');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');
    gateway.throwTransient = true;

    for (var i = 0; i < 8; i++) {
      await (db.update(db.syncOutbox)).write(
        SyncOutboxCompanion(nextRetryAt: Value(DateTime.now().subtract(const Duration(hours: 1)))),
      );
      await drainer.drainOnce();
    }

    final row = (await db.select(db.syncOutbox).get()).single;
    expect(row.deadLettered, isTrue);

    gateway.throwTransient = false;
    final res = await drainer.drainOnce();
    expect(res.pushed, 0);
    expect(gateway.upsertCount, 0);
    expect((await db.select(db.syncOutbox).get()).single.deadLettered, isTrue);
  });

  test('permanent error dead-letters immediately', () async {
    await insertAccount('a1');
    await enqueueOutboxRow(db, 'accounts', 'a1', 'upsert');
    gateway.throwPermanent = true;

    final res = await drainer.drainOnce();
    expect(res.deadLettered, 1);
    expect((await db.select(db.syncOutbox).get()).single.deadLettered, isTrue);
  });

  test('outbox row for a vanished entity (no tombstone) is dropped without a push', () async {
    await enqueueOutboxRow(db, 'accounts', 'ghost', 'upsert');
    final res = await drainer.drainOnce();
    expect(gateway.upsertCount, 0);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
    expect(res.remaining, 0);
  });

  test('a soft-deleted entity still pushes a tombstone row', () async {
    final m = await insertAccount('a1');
    await (db.update(db.accounts)..where((t) => t.id.equals('a1'))).write(
      AccountsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now()), updatedAt: Value(m.updatedAt)),
    );
    await enqueueOutboxRow(db, 'accounts', 'a1', 'delete');

    await drainer.drainOnce();
    expect(gateway.row('accounts', 'a1')!['is_deleted'], true);
  });
}
