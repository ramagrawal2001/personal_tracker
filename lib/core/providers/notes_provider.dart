import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/note_model.dart';
import '../database/app_database.dart';
import '../database/finance_repository.dart' show appDatabaseProvider;
import '../database/note_mappers.dart';
import '../sync/cloud_mappers.dart';
import '../sync/outbox_write_through.dart';

const _uuid = Uuid();

class NotesState {
  final List<NoteModel> notes;
  NotesState({this.notes = const []});

  List<NoteModel> get pinned => notes.where((n) => n.isPinned && !n.isArchived).toList();
  List<NoteModel> get unpinned => notes.where((n) => !n.isPinned && !n.isArchived).toList();
  List<NoteModel> get archived => notes.where((n) => n.isArchived).toList();

  NotesState copyWith({List<NoteModel>? notes}) =>
      NotesState(notes: notes ?? this.notes);
}

class NotesNotifier extends StateNotifier<NotesState> with OutboxWriteThrough {
  final AppDatabase _db;

  @override
  AppDatabase get db => _db;

  NotesNotifier(this._db) : super(NotesState()) {
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    try {
      final notes = (await (_db.select(_db.notes)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = NotesState(notes: notes);
    } catch (e) {
      debugPrint('NotesNotifier: failed to load persisted notes: $e');
    }
  }

  void _persist(NoteModel note) async {
    try {
      await writeThrough('notes', note.id,
          () => _db.into(_db.notes).insertOnConflictUpdate(note.toCompanion()));
    } catch (e) {
      debugPrint('NotesNotifier: failed to persist note: $e');
    }
  }

  NoteModel createNote() {
    final now = DateTime.now();
    return NoteModel(id: _uuid.v4(), createdAt: now, updatedAt: now);
  }

  void saveNote(NoteModel note) {
    if (note.isEmpty) return;
    final idx = state.notes.indexWhere((n) => n.id == note.id);
    if (idx == -1) {
      state = state.copyWith(notes: [note, ...state.notes]);
    } else {
      final updated = List<NoteModel>.from(state.notes);
      updated[idx] = note;
      state = state.copyWith(notes: updated);
    }
    _persist(note);
  }

  // ── Undo-delete window (see FinanceNotifier for the rationale) ──────────────
  static const Duration _undoWindow = Duration(seconds: 8);
  final Map<String, ({Map<String, dynamic> row, DateTime at})> _recentlyDeleted = {};

  bool canUndoDelete(String id) {
    final s = _recentlyDeleted['notes:$id'];
    return s != null && DateTime.now().difference(s.at) <= _undoWindow;
  }

  void deleteNote(String id) async {
    final gone = state.notes.where((n) => n.id == id).toList();
    state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
    if (gone.isNotEmpty) {
      final now = DateTime.now();
      _recentlyDeleted.removeWhere((_, v) => now.difference(v.at) > _undoWindow);
      _recentlyDeleted['notes:$id'] = (row: gone.first.toCloudJson(), at: now);
    }
    try {
      final now = DateTime.now();
      await deleteThrough('notes', id, () => (_db.update(_db.notes)..where((n) => n.id.equals(id)))
          .write(NotesCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now))));
    } catch (e) {
      debugPrint('NotesNotifier: failed to delete note: $e');
    }
  }

  /// Reverses a just-performed [deleteNote]. Wired to the "Undo" SnackBar action.
  Future<void> undoDelete(String id) async {
    final stash = _recentlyDeleted.remove('notes:$id');
    if (stash == null || DateTime.now().difference(stash.at) > _undoWindow) return;
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.syncOutbox)
              ..where((o) => o.entityTable.equals('notes') & o.entityId.equals(id)))
            .go();
        await (_db.delete(_db.syncMeta)..where((m) => m.key.equals('deleted:notes:$id'))).go();
      });
    } catch (e) {
      debugPrint('NotesNotifier.undoDelete cleanup failed: $e');
    }
    final row = Map<String, dynamic>.from(stash.row)
      ..['is_deleted'] = false
      ..['deleted_at'] = null
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    applyRemoteUpsert(row); // writes Drift + state, guarded (no enqueue)
    try {
      await enqueueOutbox('notes', id, 'upsert');
    } catch (e) {
      debugPrint('NotesNotifier.undoDelete re-enqueue failed: $e');
    }
  }

  // ── Remote-apply (Phase 2/3 consumers; guarded so writes never re-enqueue) ──

  void applyRemoteUpsert(Map<String, dynamic> row) {
    applyingRemote = true;
    try {
      final note = NoteCloud.fromCloud(row);
      _fireAndForget(() => _db.into(_db.notes).insertOnConflictUpdate(note.toCompanion()));
      final next = state.notes.where((n) => n.id != note.id).toList();
      if (!note.isDeleted) next.insert(0, note);
      next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(notes: next);
    } finally {
      applyingRemote = false;
    }
  }

  void applyRemoteDelete(String id) {
    applyingRemote = true;
    try {
      state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
      final now = DateTime.now();
      _fireAndForget(() => (_db.update(_db.notes)..where((n) => n.id.equals(id)))
          .write(NotesCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now))));
    } finally {
      applyingRemote = false;
    }
  }

  void _fireAndForget(Future<void> Function() op) {
    op().catchError((Object e) {
      debugPrint('NotesNotifier: remote-apply write failed: $e');
    });
  }

  void togglePin(String id) {
    NoteModel? updated;
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) {
          updated = n.copyWith(isPinned: !n.isPinned);
          return updated!;
        }
        return n;
      }).toList(),
    );
    if (updated != null) _persist(updated!);
  }

  void toggleArchive(String id) {
    NoteModel? updated;
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) {
          updated = n.copyWith(isArchived: !n.isArchived, isPinned: false);
          return updated!;
        }
        return n;
      }).toList(),
    );
    if (updated != null) _persist(updated!);
  }

  void updateColor(String id, NoteColor color) {
    NoteModel? updated;
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) {
          updated = n.copyWith(color: color);
          return updated!;
        }
        return n;
      }).toList(),
    );
    if (updated != null) _persist(updated!);
  }

  List<NoteModel> search(String query) {
    if (query.isEmpty) return state.notes.where((n) => !n.isArchived).toList();
    final q = query.toLowerCase();
    return state.notes.where((n) =>
      !n.isArchived &&
      (n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q))
    ).toList();
  }
}

final notesProvider = StateNotifierProvider<NotesNotifier, NotesState>(
  (ref) => NotesNotifier(ref.watch(appDatabaseProvider)),
);
