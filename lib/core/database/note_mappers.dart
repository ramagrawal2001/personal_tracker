import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/note_model.dart';
import 'app_database.dart';

extension NoteEntryMapper on NoteEntry {
  NoteModel toModel() {
    final rawChecklist = jsonDecode(checklistItemsJson) as List<dynamic>;
    final rawLabels = jsonDecode(labelsJson) as List<dynamic>;
    return NoteModel(
      id: id,
      title: title,
      body: body,
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
      title: Value(title),
      body: Value(body),
      color: Value(color.name),
      isPinned: Value(isPinned),
      isArchived: Value(isArchived),
      isChecklist: Value(isChecklist),
      checklistItemsJson: Value(jsonEncode(checklistItems.map((e) => e.toMap()).toList())),
      labelsJson: Value(jsonEncode(labels)),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
      deletedAt: Value(isDeleted ? DateTime.now() : null),
    );
  }
}
