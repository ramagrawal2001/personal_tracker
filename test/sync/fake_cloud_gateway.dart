import 'dart:async';

import 'package:aspyric/core/sync/cloud_gateway.dart';

/// In-memory [CloudGateway] for unit tests. Stores upserted rows keyed by
/// `table -> id`, with toggles to simulate offline / transient / permanent
/// failures and an injectable clock.
class FakeCloudGateway implements CloudGateway {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};
  final StreamController<RemoteChange> _changes = StreamController<RemoteChange>.broadcast();

  bool available = true;
  bool throwTransient = false;
  bool throwPermanent = false;
  int upsertCount = 0;
  final List<String> upsertedTables = [];
  final List<String> upsertedIds = [];

  DateTime Function() clock = DateTime.now;

  @override
  bool get isAvailable => available;

  @override
  Future<DateTime> upsertRow(String table, Map<String, dynamic> row) async {
    if (!available || throwTransient) {
      throw SyncTransientError('fake offline/transient');
    }
    if (throwPermanent) {
      throw SyncPermanentError('fake permanent');
    }
    upsertCount++;
    upsertedTables.add(table);
    final id = (row['id'] ?? row['user_id']) as String;
    upsertedIds.add(id);
    final ts = clock().toUtc();
    final stored = Map<String, dynamic>.from(row)..['updated_at'] = ts.toIso8601String();
    (store[table] ??= <String, Map<String, dynamic>>{})[id] = stored;
    return ts.toLocal();
  }

  int rowCount([String? table]) {
    if (table != null) return store[table]?.length ?? 0;
    return store.values.fold(0, (sum, m) => sum + m.length);
  }

  Map<String, dynamic>? row(String table, String id) => store[table]?[id];

  void pushRemote(RemoteChange change) => _changes.add(change);

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    DateTime? since,
    int limit = 500,
    int offset = 0,
  }) async {
    final rows = store[table]?.values.toList() ?? const <Map<String, dynamic>>[];
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Stream<RemoteChange> subscribe(String userId, List<String> tables) => _changes.stream;

  @override
  Future<void> unsubscribe() async {}

  @override
  Object get connectionState => available ? 'connected' : 'disconnected';

  Future<void> dispose() => _changes.close();
}
