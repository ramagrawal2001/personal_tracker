import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../domain/models/note_model.dart';
import '../../../../core/theme/app_colors.dart';

/// Returns dark or light text colour based on background luminance
Color _cardTextColor(Color bg) =>
    bg.computeLuminance() > 0.3 ? const Color(0xFF1A1A2E) : Colors.white;

Color _cardHintColor(Color bg) =>
    bg.computeLuminance() > 0.3 ? const Color(0x801A1A2E) : const Color(0x80FFFFFF);

class NoteCard extends StatelessWidget {
  final NoteModel note;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bg = note.color.color;
    final textColor = _cardTextColor(bg);
    final hintColor = _cardHintColor(bg);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: note.color.borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            if (note.title.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.isPinned)
                    Icon(LucideIcons.pin, size: 14, color: textColor),
                ],
              ),
              const SizedBox(height: 6),
            ],
            // Body or Checklist preview
            if (note.isChecklist && note.checklistItems.isNotEmpty)
              ...note.checklistItems.take(4).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      item.isChecked ? LucideIcons.checkSquare : LucideIcons.square,
                      size: 14,
                      color: item.isChecked ? AppColors.income : hintColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.text,
                        style: TextStyle(
                          fontSize: 13,
                          color: item.isChecked ? hintColor : textColor,
                          decoration: item.isChecked ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ))
            else if (note.body.isNotEmpty)
              Text(
                note.body,
                style: TextStyle(fontSize: 13, color: hintColor),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 10),
            // Actions row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionBtn(icon: note.isPinned ? LucideIcons.pinOff : LucideIcons.pin, onTap: onPin, color: textColor),
                _ActionBtn(icon: note.isArchived ? LucideIcons.archiveRestore : LucideIcons.archive, onTap: onArchive, color: textColor),
                _ActionBtn(icon: LucideIcons.trash2, onTap: onDelete, color: AppColors.expense),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? _color;
  Color get color => _color ?? AppColors.textMuted;

  // Not const: the default colour resolves from the (mutable) AppColors palette.
  // ignore: prefer_const_constructors_in_immutables
  _ActionBtn({required this.icon, required this.onTap, Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
