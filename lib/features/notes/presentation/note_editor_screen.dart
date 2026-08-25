import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../domain/models/note_model.dart';

const _uuid = Uuid();

class NoteEditorScreen extends ConsumerStatefulWidget {
  final NoteModel? note;
  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late NoteModel _note;
  final List<TextEditingController> _checkCtrl = [];

  @override
  void initState() {
    super.initState();
    _note = widget.note ?? ref.read(notesProvider.notifier).createNote();
    _titleCtrl = TextEditingController(text: _note.title);
    _bodyCtrl = TextEditingController(text: _note.body);
    for (final item in _note.checklistItems) {
      _checkCtrl.add(TextEditingController(text: item.text));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    for (final c in _checkCtrl) { c.dispose(); }
    super.dispose();
  }

  void _save() {
    List<NoteChecklistItem> items = [];
    if (_note.isChecklist) {
      for (int i = 0; i < _checkCtrl.length; i++) {
        final text = _checkCtrl[i].text.trim();
        if (text.isNotEmpty) {
          final original = i < _note.checklistItems.length ? _note.checklistItems[i] : null;
          items.add(NoteChecklistItem(
            id: original?.id ?? _uuid.v4(),
            text: text,
            isChecked: original?.isChecked ?? false,
          ));
        }
      }
    }
    final updated = _note.copyWith(
      title: _titleCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
      checklistItems: items,
    );
    ref.read(notesProvider.notifier).saveNote(updated);
  }

  void _addCheckItem() {
    setState(() {
      _note = _note.copyWith(
        checklistItems: [..._note.checklistItems, NoteChecklistItem(id: _uuid.v4(), text: '')],
      );
      _checkCtrl.add(TextEditingController());
    });
  }

  void _toggleChecklist() {
    setState(() {
      _note = _note.copyWith(isChecklist: !_note.isChecklist);
      
    });
  }

  void _setColor(NoteColor color) {
    setState(() {
      _note = _note.copyWith(color: color);
    });
  }

  /// Returns black or white depending on note background luminance
  Color _textColor() {
    final bg = _note.color.color;
    final luminance = bg.computeLuminance();
    return luminance > 0.3 ? const Color(0xFF1A1A2E) : Colors.white;
  }

  Color _hintColor() {
    final bg = _note.color.color;
    final luminance = bg.computeLuminance();
    return luminance > 0.3 ? const Color(0x801A1A2E) : const Color(0x80FFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _save();
        Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: _note.color.color,
      appBar: AppBar(
        backgroundColor: _note.color.color,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_note.isPinned ? LucideIcons.pinOff : LucideIcons.pin, color: AppColors.textPrimary),
            onPressed: () {
              setState(() {
                _note = _note.copyWith(isPinned: !_note.isPinned);
                
              });
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.palette, color: AppColors.textPrimary),
            onPressed: () => _showColorPicker(context),
          ),
          IconButton(
            icon: Icon(_note.isChecklist ? LucideIcons.fileText : LucideIcons.checkSquare, color: AppColors.textPrimary),
            onPressed: _toggleChecklist,
            tooltip: _note.isChecklist ? 'Switch to Note' : 'Switch to Checklist',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              onChanged: (_) {},
              cursorColor: _textColor(),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor()),
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: _hintColor(), fontWeight: FontWeight.bold, fontSize: 22),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            if (_note.isChecklist) ...[
              ...List.generate(_checkCtrl.length, (i) {
                final isChecked = i < _note.checklistItems.length ? _note.checklistItems[i].isChecked : false;
                return Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          final items = List<NoteChecklistItem>.from(_note.checklistItems);
                          if (i < items.length) {
                            items[i] = items[i].copyWith(isChecked: !items[i].isChecked);
                            _note = _note.copyWith(checklistItems: items);
                          }
                        });
                      },
                      child: Icon(
                        isChecked ? LucideIcons.checkSquare : LucideIcons.square,
                        color: isChecked ? AppColors.income : _hintColor(),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _checkCtrl[i],
                        onChanged: (_) {},
                        cursorColor: _textColor(),
                        style: TextStyle(
                          color: _textColor(),
                          decoration: isChecked ? TextDecoration.lineThrough : null,
                        ),
                        decoration: InputDecoration(
                          hintText: 'List item',
                          hintStyle: TextStyle(color: _hintColor()),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: _hintColor()),
                      onPressed: () {
                        setState(() {
                          _checkCtrl.removeAt(i);
                          if (i < _note.checklistItems.length) {
                            final items = List<NoteChecklistItem>.from(_note.checklistItems)..removeAt(i);
                            _note = _note.copyWith(checklistItems: items);
                          }
                        });
                      },
                    ),
                  ],
                );
              }),
              // ── Add item button — only visible in checklist mode ──
              TextButton.icon(
                onPressed: _addCheckItem,
                icon: Icon(LucideIcons.plus, size: 16, color: _textColor()),
                label: Text('Add item', style: TextStyle(color: _textColor())),
                style: TextButton.styleFrom(foregroundColor: _textColor()),
              ),
            ] else
              // ── Body text field — regular note mode ──
              TextField(
                controller: _bodyCtrl,
                onChanged: (_) {},
                maxLines: null,
                minLines: 8,
                cursorColor: _textColor(),
                style: TextStyle(color: _textColor(), fontSize: 16, height: 1.6),
                decoration: InputDecoration(
                  hintText: 'Start typing your note…',
                  hintStyle: TextStyle(color: _hintColor()),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Note Color', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: NoteColor.values.map((c) {
                  return GestureDetector(
                    onTap: () {
                      _setColor(c);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _note.color == c ? AppColors.primary : c.borderColor,
                          width: _note.color == c ? 3 : 1.5,
                        ),
                      ),
                      child: _note.color == c
                          ? const Icon(LucideIcons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
