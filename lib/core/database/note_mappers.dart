import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/note_model.dart';
import '../services/secret_cipher_service.dart';
import 'app_database.dart';

// Notes are stored ENCRYPTED at rest: the operator (local SQLite / Supabase
// tables) only ever sees ciphertext in `title` / `body` / `checklistItemsJson`
// / `labelsJson`. The in-memory [NoteModel] always carries plaintext, so every
// note widget is unchanged. `color` / pin / archive / timestamps stay plaintext
// — they aren't sensitive and the list needs them to filter and sort.
String _dec(String stored) => SecretCipherService.decField(stored);
String _enc(String plaintext) => SecretCipherService.encField(plaintext);

List<dynamic> _decodeJsonList(String stored) {
  final s = _dec(stored).trim();
  if (s.isEmpty) return const [];
  try {
    final v = jsonDecode(s);
    return v is List ? v : const [];
  } catch (_) {
    return const [];
  }
}

extension NoteEntryMapper on NoteEntry {
  NoteModel toModel() {
    final rawChecklist = _decodeJsonList(checklistItemsJson);
    final rawLabels = _decodeJsonList(labelsJson);
    return NoteModel(
      id: id,
      title: _dec(title),
      body: _dec(body),
      color: NoteColor.values.byName(color),
      isPinned: isPinned,
      isArchived: isArchived,
      isChecklist: isChecklist,
      checklistItems: rawChecklist
          .map((e) => NoteChecklistItem.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
      labels: rawLabels.cast<String>(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

extension NoteModelMapper on NoteModel {
  NotesCompanion toCompanion() {
    return NotesCompanion(
      id: Value(id),
      title: Value(_enc(title)),
      body: Value(_enc(body)),
      color: Value(color.name),
      isPinned: Value(isPinned),
      isArchived: Value(isArchived),
      isChecklist: Value(isChecklist),
      checklistItemsJson:
          Value(_enc(jsonEncode(checklistItems.map((e) => e.toMap()).toList()))),
      labelsJson: Value(_enc(jsonEncode(labels))),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}
