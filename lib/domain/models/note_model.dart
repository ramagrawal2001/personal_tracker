import 'package:flutter/material.dart';

class NoteChecklistItem {
  final String id;
  final String text;
  final bool isChecked;

  const NoteChecklistItem({
    required this.id,
    required this.text,
    this.isChecked = false,
  });

  NoteChecklistItem copyWith({String? text, bool? isChecked}) {
    return NoteChecklistItem(
      id: id,
      text: text ?? this.text,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'isChecked': isChecked};
  factory NoteChecklistItem.fromMap(Map<String, dynamic> m) =>
      NoteChecklistItem(id: m['id'], text: m['text'], isChecked: m['isChecked'] ?? false);
}

enum NoteColor {
  defaultColor,
  red,
  orange,
  yellow,
  green,
  teal,
  blue,
  purple,
  pink,
}

extension NoteColorExt on NoteColor {
  Color get color {
    switch (this) {
      case NoteColor.red: return const Color(0xFF4A1942);
      case NoteColor.orange: return const Color(0xFF5C3317);
      case NoteColor.yellow: return const Color(0xFF4A4000);
      case NoteColor.green: return const Color(0xFF1A3A1A);
      case NoteColor.teal: return const Color(0xFF0D3B3B);
      case NoteColor.blue: return const Color(0xFF0D2137);
      case NoteColor.purple: return const Color(0xFF2D1B69);
      case NoteColor.pink: return const Color(0xFF4A1429);
      default: return const Color(0xFF1E2035);
    }
  }

  Color get borderColor {
    switch (this) {
      case NoteColor.red: return const Color(0xFFE57373);
      case NoteColor.orange: return const Color(0xFFFFB74D);
      case NoteColor.yellow: return const Color(0xFFFFF176);
      case NoteColor.green: return const Color(0xFF81C784);
      case NoteColor.teal: return const Color(0xFF4DB6AC);
      case NoteColor.blue: return const Color(0xFF64B5F6);
      case NoteColor.purple: return const Color(0xFFBA68C8);
      case NoteColor.pink: return const Color(0xFFF48FB1);
      default: return const Color(0xFF2A2D3E);
    }
  }
}

class NoteModel {
  final String id;
  final String title;
  final String body;
  final NoteColor color;
  final bool isPinned;
  final bool isArchived;
  final bool isChecklist;
  final List<NoteChecklistItem> checklistItems;
  final List<String> labels;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const NoteModel({
    required this.id,
    this.title = '',
    this.body = '',
    this.color = NoteColor.defaultColor,
    this.isPinned = false,
    this.isArchived = false,
    this.isChecklist = false,
    this.checklistItems = const [],
    this.labels = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  bool get isEmpty => title.isEmpty && body.isEmpty && checklistItems.isEmpty;

  NoteModel copyWith({
    String? title,
    String? body,
    NoteColor? color,
    bool? isPinned,
    bool? isArchived,
    bool? isChecklist,
    List<NoteChecklistItem>? checklistItems,
    List<String>? labels,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return NoteModel(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      color: color ?? this.color,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isChecklist: isChecklist ?? this.isChecklist,
      checklistItems: checklistItems ?? this.checklistItems,
      labels: labels ?? this.labels,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
