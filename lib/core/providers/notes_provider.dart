import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/note_model.dart';

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
  NotesNotifier() : super(NotesState());

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
  }

  void deleteNote(String id) {
    state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
  }

  void togglePin(String id) {
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) return n.copyWith(isPinned: !n.isPinned);
        return n;
      }).toList(),
    );
  }

  void toggleArchive(String id) {
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) return n.copyWith(isArchived: !n.isArchived, isPinned: false);
        return n;
      }).toList(),
    );
  }

  void updateColor(String id, NoteColor color) {
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) return n.copyWith(color: color);
        return n;
      }).toList(),
    );
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
  (ref) => NotesNotifier(),
);
