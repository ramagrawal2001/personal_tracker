import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/finance_repository.dart' show financeNotifierProvider;
import '../providers/notes_provider.dart' show notesProvider;
import 'sync_service.dart' show RemoteApplySink;

/// Routes a remote change to the right notifier. Phase 2/3 feed this from pull
/// results and realtime events; in Phase 1 it is constructed and held but never
/// invoked.
class RiverpodRemoteApplySink implements RemoteApplySink {
  final Ref ref;

  RiverpodRemoteApplySink(this.ref);

  @override
  void applyRemote(String table, Map<String, dynamic> row) {
    final deleted = row['is_deleted'] == true;
    final id = row['id'] as String?;

    if (table == 'notes') {
      final notes = ref.read(notesProvider.notifier);
      if (deleted && id != null) {
        notes.applyRemoteDelete(id);
      } else {
        notes.applyRemoteUpsert(row);
      }
      return;
    }

    if (table == 'user_settings') {
      ref.read(financeNotifierProvider.notifier).applyRemoteSettings(row);
      return;
    }

    final finance = ref.read(financeNotifierProvider.notifier);
    if (deleted && id != null) {
      finance.applyRemoteDelete(table, id);
    } else {
      finance.applyRemoteUpsert(table, row);
    }
  }
}
