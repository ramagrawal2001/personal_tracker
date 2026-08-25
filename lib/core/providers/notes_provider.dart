import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/note_model.dart';
import '../database/app_database.dart';
import '../database/finance_repository.dart' show appDatabaseProvider;
import '../database/note_mappers.dart';

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

class NotesNotifier extends StateNotifier<NotesState> {
  final AppDatabase _db;

  NotesNotifier(this._db) : super(NotesState()) {
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    try {
      final notes = (await _db.select(_db.notes).get()).map((e) => e.toModel()).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = NotesState(notes: notes);
    } catch (e) {
      debugPrint('NotesNotifier: failed to load persisted notes: $e');
    }
  }

  void _persist(NoteModel note) async {
    try {
      await _db.into(_db.notes).insertOnConflictUpdate(note.toCompanion());
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

  void deleteNote(String id) async {
    state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
    try {
      await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
    } catch (e) {
      debugPrint('NotesNotifier: failed to delete note: $e');
    }
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
