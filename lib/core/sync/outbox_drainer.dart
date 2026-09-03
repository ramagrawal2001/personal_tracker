import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../database/finance_mappers.dart';
import '../database/note_mappers.dart';
import 'cloud_gateway.dart';
import 'cloud_mappers.dart';

class OutboxDrainResult {
  final int pushed;
  final int failed;
  final int deadLettered;
  final int remaining;

  const OutboxDrainResult({
    this.pushed = 0,
    this.failed = 0,
    this.deadLettered = 0,
    this.remaining = 0,
  });
}

/// Pure, independently-testable outbox pump. One [drainOnce] call pushes up to
/// 50 ready rows through the [CloudGateway] and updates their retry/dead-letter
/// bookkeeping. It never touches Riverpod — [SyncService] owns scheduling.
class OutboxDrainer {
  final AppDatabase db;
  final CloudGateway gateway;
  final Random _rng = Random();

  static const int _batchSize = 50;
  static const int _maxAttempts = 8;

  OutboxDrainer({required this.db, required this.gateway});

  Future<OutboxDrainResult> drainOnce() async {
    final now = DateTime.now();
    final rows = await (db.select(db.syncOutbox)
          ..where((r) => r.deadLettered.equals(false) & r.nextRetryAt.isSmallerOrEqualValue(now))
          ..orderBy([(r) => OrderingTerm.asc(r.seq)])
          ..limit(_batchSize))
        .get();

    int pushed = 0;
    int failed = 0;
    int dead = 0;

    for (final row in rows) {
      try {
        final cloudRow = await _buildCloudRow(row.entityTable, row.entityId);
        if (cloudRow == null) {
          // Entity no longer exists locally and left no tombstone — nothing to
          // push. Drop the queue row.
          await _deleteRow(row.id, row.seq);
          pushed++;
          continue;
        }
        await gateway.upsertRow(row.entityTable, cloudRow);
        // Only remove the row if no newer edit re-stamped its seq mid-push.
        await _deleteRow(row.id, row.seq);
        pushed++;
      } on SyncPermanentError catch (e) {
        await _markDead(row.id, e.toString());
        dead++;
      } on SyncTransientError catch (e) {
        final handled = await _backoff(row.id, row.attempts, e.toString());
        handled ? dead++ : failed++;
      } catch (e) {
        // Unknown error: treat conservatively as transient.
        final handled = await _backoff(row.id, row.attempts, e.toString());
        handled ? dead++ : failed++;
      }
    }

    return OutboxDrainResult(
      pushed: pushed,
      failed: failed,
      deadLettered: dead,
      remaining: await pendingCount(),
    );
  }

  Future<int> pendingCount() async {
    final rows = await (db.select(db.syncOutbox)..where((r) => r.deadLettered.equals(false))).get();
    return rows.length;
  }

  Future<int> deadLetterCount() async {
    final rows = await (db.select(db.syncOutbox)..where((r) => r.deadLettered.equals(true))).get();
    return rows.length;
  }

  // ── internals ─────────────────────────────────────────────────────────────

  Future<void> _deleteRow(int id, int seq) async {
    await (db.delete(db.syncOutbox)..where((r) => r.id.equals(id) & r.seq.equals(seq))).go();
  }

  Future<void> _markDead(int id, String error) async {
    await (db.update(db.syncOutbox)..where((r) => r.id.equals(id))).write(SyncOutboxCompanion(
      deadLettered: const Value(true),
      lastError: Value(error),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Returns true when the row was dead-lettered (attempt ceiling reached).
  Future<bool> _backoff(int id, int currentAttempts, String error) async {
    final attempts = currentAttempts + 1;
    if (attempts >= _maxAttempts) {
      await _markDead(id, error);
      return true;
    }
    final seconds = min(pow(2, attempts).toInt() * 2, 600) + _rng.nextInt(5);
    await (db.update(db.syncOutbox)..where((r) => r.id.equals(id))).write(SyncOutboxCompanion(
      attempts: Value(attempts),
      lastError: Value(error),
      nextRetryAt: Value(DateTime.now().add(Duration(seconds: seconds))),
      updatedAt: Value(DateTime.now()),
    ));
    return false;
  }

  Future<Map<String, dynamic>?> _buildCloudRow(String table, String id) async {
    switch (table) {
      case 'accounts':
        final r = await (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'categories':
        final r = await (db.select(db.categories)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'transactions':
        final r = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'credit_cards':
        final r = await (db.select(db.creditCards)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'loans':
        final r = await (db.select(db.loans)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'budgets':
        final r = await (db.select(db.budgets)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'recurring_payments':
        final r = await (db.select(db.recurringPayments)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'investments':
        final r = await (db.select(db.investments)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'goals':
        final r = await (db.select(db.goals)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'notes':
        final r = await (db.select(db.notes)..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.toModel().toCloudJson();
      case 'user_settings':
        return _buildSettingsRow(id);
      default:
        debugPrint('OutboxDrainer: unknown entity table "$table"');
        return null;
    }
  }

  Future<Map<String, dynamic>> _buildSettingsRow(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final metaRow = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('settings_updated_at')))
        .getSingleOrNull();
    final updatedAt = metaRow == null ? DateTime.now() : DateTime.tryParse(metaRow.value) ?? DateTime.now();
    return settingsToCloudJson(
      userId,
      emergencyBuffer: prefs.getDouble(kPrefEmergencyBuffer) ?? 20000.0,
      currencySymbol: prefs.getString(kPrefCurrencySymbol) ?? '₹',
      isRoundUpEnabled: prefs.getBool(kPrefRoundUpEnabled) ?? false,
      isAutoBackupEnabled: prefs.getBool(kPrefAutoBackupEnabled) ?? false,
      updatedAt: updatedAt,
    );
  }
}
