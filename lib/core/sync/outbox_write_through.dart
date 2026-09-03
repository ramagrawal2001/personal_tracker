import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Enqueues (or coalesces) a single [SyncOutbox] row for `(table, id)`.
///
/// Uses an explicit `DoUpdate` targeting the `{entity_table, entity_id}` unique
/// index so repeated edits to one entity collapse onto one pending row and a
/// fresh edit re-arms a previously failed / dead-lettered row.
Future<void> enqueueOutboxRow(
  AppDatabase db,
  String table,
  String id,
  String op, {
  int? seq,
}) async {
  final now = DateTime.now();
  final resolvedSeq = seq ?? now.microsecondsSinceEpoch;
  await db.into(db.syncOutbox).insert(
        SyncOutboxCompanion.insert(
          entityTable: table,
          entityId: id,
          op: op,
          seq: resolvedSeq,
          nextRetryAt: Value(now),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
        onConflict: DoUpdate(
          (_) => SyncOutboxCompanion(
            op: Value(op),
            seq: Value(resolvedSeq),
            attempts: const Value(0),
            lastError: const Value(null),
            nextRetryAt: Value(now),
            deadLettered: const Value(false),
            updatedAt: Value(now),
          ),
          target: [db.syncOutbox.entityTable, db.syncOutbox.entityId],
        ),
      );
}

/// Mixed into [FinanceNotifier] and [NotesNotifier]. Every local mutation goes
/// through [writeThrough] / [deleteThrough], which perform the Drift write and
/// (unless we are currently applying a remote change) enqueue a matching outbox
/// row inside the *same* transaction.
mixin OutboxWriteThrough {
  AppDatabase get db;

  /// Set while applying a change that came *from* the cloud, so the write-back
  /// does not re-enqueue an outbox row (which would echo forever).
  bool applyingRemote = false;

  Future<void> writeThrough(
    String table,
    String id,
    Future<void> Function() dbWrite,
  ) async {
    await db.transaction(() async {
      await dbWrite();
      if (!applyingRemote) {
        await enqueueOutboxRow(db, table, id, 'upsert');
      }
    });
  }

  Future<void> deleteThrough(
    String table,
    String id,
    Future<void> Function() softDelete,
  ) async {
    await db.transaction(() async {
      await softDelete();
      if (!applyingRemote) {
        await enqueueOutboxRow(db, table, id, 'delete');
      }
    });
  }

  /// Direct enqueue for rows that are not a plain entity write (e.g. the
  /// synthetic `user_settings` row).
  Future<void> enqueueOutbox(String table, String id, String op) =>
      enqueueOutboxRow(db, table, id, op);
}
