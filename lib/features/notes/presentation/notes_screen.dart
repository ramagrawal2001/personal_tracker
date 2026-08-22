import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../domain/models/note_model.dart';
import 'widgets/note_card_widget.dart';
import 'note_editor_screen.dart';

enum NotesView { all, pinned, archived }

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
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('NOTES', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, color: AppColors.primary),
            onPressed: () => _openEditor(null),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search notes…',
                prefixIcon: const Icon(LucideIcons.search, color: AppColors.textMuted, size: 20),
                suffixIcon: query.isNotEmpty
                    ? IconButton(icon: const Icon(LucideIcons.x, size: 18, color: AppColors.textMuted), onPressed: () { _searchCtrl.clear(); setState(() {}); })
                    : null,
              ),
            ),
          ),
          // View tabs
          if (query.isEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _TabChip('All', NotesView.all),
                  _TabChip('Pinned', NotesView.pinned),
                  _TabChip('Archived', NotesView.archived),
                ],
              ),
            ),
          // Notes grid
          Expanded(
            child: totalCount == 0 && pinned.isEmpty
                ? _EmptyState(view: _view, onAdd: () => _openEditor(null))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pinned.isNotEmpty && query.isEmpty) ...[
                          const Text('PINNED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
                          const SizedBox(height: 10),
                          _NotesGrid(notes: pinned, notifier: notifier, onTap: _openEditor),
                          const SizedBox(height: 20),
                          if (others.isNotEmpty)
                            const Text('OTHERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
                          const SizedBox(height: 10),
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

  Widget _TabChip(String label, NotesView view) {
    final selected = _view == view;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
        onSelected: (_) => setState(() => _view = view),
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
          onArchive: () => notifier.toggleArchive(note.id),
          onDelete: () => notifier.deleteNote(note.id),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NotesView view;
  final VoidCallback onAdd;
  const _EmptyState({required this.view, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isArchived = view == NotesView.archived;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isArchived ? LucideIcons.archive : LucideIcons.stickyNote, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(isArchived ? 'No archived notes' : 'No notes yet', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(isArchived ? 'Notes you archive appear here' : 'Tap + to create your first note', style: const TextStyle(color: AppColors.textMuted)),
          if (!isArchived) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('New Note'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ],
      ),
    );
  }
}
