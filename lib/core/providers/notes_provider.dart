import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/note_model.dart';
import '../database/app_database.dart';
import '../database/finance_repository.dart' show appDatabaseProvider;
import '../database/note_mappers.dart';
import '../services/secret_cipher_service.dart';
import '../services/supabase_service.dart';
import '../sync/cloud_mappers.dart';
import '../sync/cloud_direct_write.dart';

const _uuid = Uuid();

/// Page size for [NotesNotifier.refreshFromCloud]'s paginated fetch — matches
/// the page size the old sync engine used.
const int _kRefreshPageSize = 500;

class NotesState {
  final List<NoteModel> notes;
  final bool isRefreshing;
  final DateTime? lastRefreshedAt;
  final String? lastRefreshError;

  NotesState({
    this.notes = const [],
    this.isRefreshing = false,
    this.lastRefreshedAt,
    this.lastRefreshError,
  });

  List<NoteModel> get pinned => notes.where((n) => n.isPinned && !n.isArchived).toList();
  List<NoteModel> get unpinned => notes.where((n) => !n.isPinned && !n.isArchived).toList();
  List<NoteModel> get archived => notes.where((n) => n.isArchived).toList();

  NotesState copyWith({
    List<NoteModel>? notes,
    bool? isRefreshing,
    DateTime? lastRefreshedAt,
    Object? lastRefreshError = _sentinel,
  }) =>
      NotesState(
        notes: notes ?? this.notes,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
        lastRefreshError: identical(lastRefreshError, _sentinel) ? this.lastRefreshError : lastRefreshError as String?,
      );

  static const Object _sentinel = Object();
}

class NotesNotifier extends StateNotifier<NotesState> with CloudDirectWrite {
  final AppDatabase _db;

  NotesNotifier(this._db) : super(NotesState()) {
    _loadFromDb();
    SecretCipherService.readyListenable.addListener(_onCipherBecameReady);
  }

  /// Mirrors [FinanceNotifier._cipherReadyOnLoad]: `false` means the notes were
  /// mapped before the field-encryption DEK was available (session-restore cold
  /// start), so [_onCipherBecameReady] must re-read once it arrives, otherwise
  /// title / body / checklist / labels render as ciphertext.
  bool _cipherReadyOnLoad = false;

  Future<void> _loadFromDb() async {
    try {
      // Bring the DEK back from the OS keystore first so note fields decrypt on
      // a cold start instead of showing ciphertext until something else
      // triggers a reload.
      await SecretCipherService(_db).restoreFromCache();
      _cipherReadyOnLoad = _cipherReadyOnLoad || SecretCipherService.ready;
      final notes = (await (_db.select(_db.notes)..where((t) => t.isDeleted.equals(false))).get())
          .map((e) => e.toModel())
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(notes: notes);

      // Local cache is on screen — reconcile with the cloud in the background.
      // No-ops instantly for demo/offline accounts.
      if (hasCloudSession) unawaited(refreshFromCloud());
    } catch (e) {
      debugPrint('NotesNotifier: failed to load persisted notes: $e');
    }
  }

  /// Re-reads every note from Drift. Public so a vault restore or a late DEK
  /// unlock can refresh the in-memory list.
  Future<void> reloadFromDb() => _loadFromDb();

  /// Resets in-memory notes to empty. Companion to
  /// `FinanceNotifier.clearForNewUser`, which wipes the whole local DB
  /// (`notes` included) on sign-out — this just clears the in-memory mirror
  /// of it without touching Drift itself.
  void clearLocal() {
    state = NotesState();
  }

  void _onCipherBecameReady() {
    if (_cipherReadyOnLoad || !SecretCipherService.ready) return;
    _cipherReadyOnLoad = true;
    _loadFromDb();
  }

  @override
  void dispose() {
    SecretCipherService.readyListenable.removeListener(_onCipherBecameReady);
    super.dispose();
  }

  // ── Refresh from cloud ──────────────────────────────────────────────────
  // See `FinanceNotifier.refreshFromCloud` for the full rationale: no
  // realtime, no timer — convergence happens on launch/resume/manual refresh.
  // Every page is fetched before the local cache is touched, so a mid-fetch
  // failure leaves the cache untouched and only sets `lastRefreshError`.
  Future<void> refreshFromCloud() async {
    if (!hasCloudSession || state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, lastRefreshError: null);
    try {
      final rows = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        // A stable order is required, not cosmetic — see the equivalent
        // comment in FinanceNotifier._fetchAllPages.
        final page = await SupabaseService.client
            .from('notes')
            .select()
            .eq('is_deleted', false)
            .order('created_at')
            .range(offset, offset + _kRefreshPageSize - 1);
        final list = (page as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
        rows.addAll(list);
        if (list.length < _kRefreshPageSize) break;
        offset += _kRefreshPageSize;
      }

      await _db.transaction(() async {
        await _db.delete(_db.notes).go();
        for (final r in rows) {
          await _db.into(_db.notes).insertOnConflictUpdate(NoteCloud.fromCloud(r).toCompanion());
        }
      });

      final notes = rows.map(NoteCloud.fromCloud).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(notes: notes, isRefreshing: false, lastRefreshedAt: DateTime.now(), lastRefreshError: null);
    } catch (e, st) {
      debugPrint('NotesNotifier.refreshFromCloud failed: $e\n$st');
      state = state.copyWith(isRefreshing: false, lastRefreshError: e.toString());
    }
  }

  /// Pushes every locally-held (non-deleted) note straight to the cloud —
  /// used after a vault restore writes rows directly into Drift, bypassing
  /// [saveNote]. Best-effort per row.
  Future<void> pushAllToCloud() async {
    if (!hasCloudSession) return;
    for (final note in state.notes) {
      try {
        await pushToCloud('notes', note.toCloudJson());
      } catch (e) {
        debugPrint('NotesNotifier.pushAllToCloud row failed: $e');
      }
    }
  }

  NoteModel createNote() {
    final now = DateTime.now();
    return NoteModel(id: _uuid.v4(), createdAt: now, updatedAt: now);
  }

  /// Saves (creates or updates) a note. Pushes to the cloud first; on
  /// failure nothing local changes and the error propagates to the caller.
  Future<void> saveNote(NoteModel note) async {
    if (note.isEmpty) return;
    final draft = note.copyWith(updatedAt: DateTime.now());

    final serverTs = await pushToCloud('notes', draft.toCloudJson());
    final saved = serverTs != null ? draft.copyWith(updatedAt: serverTs) : draft;

    await _db.into(_db.notes).insertOnConflictUpdate(saved.toCompanion());
    final idx = state.notes.indexWhere((n) => n.id == saved.id);
    if (idx == -1) {
      state = state.copyWith(notes: [saved, ...state.notes]);
    } else {
      final updated = List<NoteModel>.from(state.notes);
      updated[idx] = saved;
      state = state.copyWith(notes: updated);
    }
  }

  // ── Undo-delete window (see FinanceNotifier for the rationale) ──────────────
  static const Duration _undoWindow = Duration(seconds: 8);
  final Map<String, ({Map<String, dynamic> row, DateTime at})> _recentlyDeleted = {};

  bool canUndoDelete(String id) {
    final s = _recentlyDeleted['notes:$id'];
    return s != null && DateTime.now().difference(s.at) <= _undoWindow;
  }

  /// Deletes a note. Pushes the tombstone to the cloud first; on failure
  /// nothing local changes and the error propagates to the caller.
  Future<void> deleteNote(String id) async {
    final gone = state.notes.where((n) => n.id == id).toList();
    if (gone.isEmpty) return;
    final now = DateTime.now();
    final tombstone = gone.first.copyWith(isDeleted: true, updatedAt: now);

    await pushToCloud('notes', tombstone.toCloudJson());

    final rowStash = gone.first.toCloudJson();
    _recentlyDeleted.removeWhere((_, v) => now.difference(v.at) > _undoWindow);
    _recentlyDeleted['notes:$id'] = (row: rowStash, at: now);

    await (_db.update(_db.notes)..where((n) => n.id.equals(id)))
        .write(NotesCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)));
    state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
  }

  /// Reverses a just-performed [deleteNote]. Wired to the "Undo" SnackBar
  /// action. Best-effort: the delete itself already succeeded, so a failure
  /// here is logged rather than surfaced.
  Future<void> undoDelete(String id) async {
    final stash = _recentlyDeleted.remove('notes:$id');
    if (stash == null || DateTime.now().difference(stash.at) > _undoWindow) return;
    try {
      final row = Map<String, dynamic>.from(stash.row)
        ..['is_deleted'] = false
        ..['deleted_at'] = null
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
      final serverTs = await pushToCloud('notes', row);
      if (serverTs != null) row['updated_at'] = serverTs.toUtc().toIso8601String();

      final note = NoteCloud.fromCloud(row);
      await _db.into(_db.notes).insertOnConflictUpdate(note.toCompanion());
      final next = state.notes.where((n) => n.id != note.id).toList()
        ..insert(0, note)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(notes: next);
    } catch (e) {
      debugPrint('NotesNotifier.undoDelete failed: $e');
    }
  }

  void _fireAndForget(Future<void> Function() op) {
    op().catchError((Object e) {
      debugPrint('NotesNotifier: background write failed: $e');
    });
  }

  /// These three stay synchronous, optimistic setters — same rationale as
  /// `FinanceNotifier`'s settings toggles: flipping pin/archive/color can
  /// never corrupt data, so the cloud push happens best-effort in the
  /// background rather than gating the UI on a round trip.
  void togglePin(String id) {
    NoteModel? updated;
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) {
          updated = n.copyWith(isPinned: !n.isPinned, updatedAt: DateTime.now());
          return updated!;
        }
        return n;
      }).toList(),
    );
    if (updated != null) _persistBestEffort(updated!);
  }

  void toggleArchive(String id) {
    NoteModel? updated;
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) {
          updated = n.copyWith(isArchived: !n.isArchived, isPinned: false, updatedAt: DateTime.now());
          return updated!;
        }
        return n;
      }).toList(),
    );
    if (updated != null) _persistBestEffort(updated!);
  }

  void updateColor(String id, NoteColor color) {
    NoteModel? updated;
    state = state.copyWith(
      notes: state.notes.map((n) {
        if (n.id == id) {
          updated = n.copyWith(color: color, updatedAt: DateTime.now());
          return updated!;
        }
        return n;
      }).toList(),
    );
    if (updated != null) _persistBestEffort(updated!);
  }

  void _persistBestEffort(NoteModel note) {
    _fireAndForget(() async {
      await _db.into(_db.notes).insertOnConflictUpdate(note.toCompanion());
      await pushToCloud('notes', note.toCloudJson());
    });
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
