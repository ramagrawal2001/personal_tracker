import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../../../domain/models/note_model.dart';
import 'widgets/note_card_widget.dart';
import 'note_editor_screen.dart';

enum NotesView { all, pinned, archived }

void _confirmDelete(BuildContext context, NotesNotifier notifier, String noteId) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Delete note?', style: TextStyle(color: AppColors.textPrimary)),
      content: Text('This cannot be undone.', style: TextStyle(color: AppColors.textMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await notifier.deleteNote(noteId);
              if (!context.mounted) return;
              showUndoDeleteSnackBar(
                context,
                message: 'Note deleted',
                onUndo: () => notifier.undoDelete(noteId),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.expense),
              );
            }
          },
          child: Text('Delete', style: TextStyle(color: AppColors.expense)),
        ),
      ],
    ),
  );
}

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchCtrl = TextEditingController();
  NotesView _view = NotesView.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openEditor(NoteModel? note) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notesProvider);
    final notifier = ref.read(notesProvider.notifier);
    final query = _searchCtrl.text.trim();

    List<NoteModel> pinned = [];
    List<NoteModel> others = [];

    if (_view == NotesView.archived) {
      others = state.archived;
    } else if (query.isNotEmpty) {
      others = notifier.search(query);
    } else if (_view == NotesView.pinned) {
      pinned = state.pinned;
    } else {
      pinned = state.pinned;
      others = state.unpinned;
    }

    final totalCount = (_view == NotesView.archived ? state.archived : state.notes.where((n) => !n.isArchived)).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Notes & Scratchpad',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.2),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.plus, color: AppColors.primary, size: 20),
            ),
            onPressed: () => _openEditor(null),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search notes & checklists…',
                prefixIcon: Icon(LucideIcons.search, color: AppColors.textMuted, size: 18),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMuted),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
          ),
          // View filter tabs
          if (query.isEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _buildTabChip('All Notes', NotesView.all),
                  _buildTabChip('Pinned', NotesView.pinned),
                  _buildTabChip('Archived', NotesView.archived),
                ],
              ),
            ),
          // Notes grid
          Expanded(
            child: totalCount == 0 && pinned.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: EmptyState(
                        icon: _view == NotesView.archived ? LucideIcons.archive : LucideIcons.stickyNote,
                        title: _view == NotesView.archived ? 'No archived notes' : 'No notes yet',
                        description: _view == NotesView.archived
                            ? 'Archived notes will be stored here safely.'
                            : 'Create financial checklists, PIN reminders, or shopping lists.',
                        actionLabel: _view == NotesView.archived ? null : 'Create Note',
                        onAction: _view == NotesView.archived ? null : () => _openEditor(null),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pinned.isNotEmpty && query.isEmpty) ...[
                          const SectionLabel(label: 'Pinned'),
                          _NotesGrid(notes: pinned, notifier: notifier, onTap: _openEditor),
                          const SizedBox(height: 20),
                          if (others.isNotEmpty) const SectionLabel(label: 'All Notes'),
                        ],
                        _NotesGrid(notes: others, notifier: notifier, onTap: _openEditor),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(null),
        backgroundColor: AppColors.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }

  Widget _buildTabChip(String label, NotesView view) {
    final selected = _view == view;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _view = view),
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _NotesGrid extends StatelessWidget {
  final List<NoteModel> notes;
  final NotesNotifier notifier;
  final void Function(NoteModel) onTap;

  const _NotesGrid({required this.notes, required this.notifier, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: notes.length,
      itemBuilder: (_, i) {
        final note = notes[i];
        return NoteCard(
          note: note,
          onTap: () => onTap(note),
          onPin: () => notifier.togglePin(note.id),
          onArchive: () {
            final wasArchived = note.isArchived;
            notifier.toggleArchive(note.id);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(wasArchived ? 'Note restored' : 'Note archived'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => notifier.toggleArchive(note.id),
                ),
              ));
          },
          onDelete: () => _confirmDelete(context, notifier, note.id),
        );
      },
    );
  }
}
