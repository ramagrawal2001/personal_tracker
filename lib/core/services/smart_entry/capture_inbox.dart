import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart';
import '../../../domain/models/models.dart';
import 'bank_message_parser.dart';
import 'native_capture_bridge.dart';
import 'parsed_transaction.dart';

/// One auto-captured transaction waiting for the user to confirm.
class CaptureItem {
  final String id;
  final CaptureSource source;
  final DateTime receivedAt;
  final ParsedTransaction draft;
  final String? sender;

  /// Id of an already-logged transaction this probably duplicates.
  final String? possibleDuplicateOf;

  const CaptureItem({
    required this.id,
    required this.source,
    required this.receivedAt,
    required this.draft,
    this.sender,
    this.possibleDuplicateOf,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'receivedAt': receivedAt.toIso8601String(),
        'draft': draft.toJson(),
        'sender': sender,
        'dup': possibleDuplicateOf,
      };

  static CaptureItem? fromJson(Map<String, dynamic> j) {
    try {
      return CaptureItem(
        id: j['id'] as String,
        source: CaptureSource.values.firstWhere((s) => s.name == j['source'], orElse: () => CaptureSource.sms),
        receivedAt: DateTime.parse(j['receivedAt'] as String),
        draft: ParsedTransaction.fromJson((j['draft'] as Map).cast<String, dynamic>()),
        sender: j['sender'] as String?,
        possibleDuplicateOf: j['dup'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class CaptureInboxState {
  final List<CaptureItem> items;

  /// Fingerprints of captures already handled (logged or dismissed), so the
  /// same SMS re-read from the inbox scan never comes back.
  final Set<String> seen;
  final bool smsEnabled;
  final bool notificationsEnabled;

  const CaptureInboxState({
    this.items = const [],
    this.seen = const {},
    this.smsEnabled = false,
    this.notificationsEnabled = false,
  });

  CaptureInboxState copyWith({List<CaptureItem>? items, Set<String>? seen, bool? smsEnabled, bool? notificationsEnabled}) =>
      CaptureInboxState(
        items: items ?? this.items,
        seen: seen ?? this.seen,
        smsEnabled: smsEnabled ?? this.smsEnabled,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      );
}

/// Device-local review inbox for auto-captured transactions (SMS, payment
/// notifications, iOS Shortcuts, shared text). Nothing here touches the
/// ledger until the user confirms an item.
class CaptureInboxNotifier extends StateNotifier<CaptureInboxState> {
  final Ref? _ref;
  final FinanceState Function() _finance;

  static const _kItems = 'capture_inbox_items_v1';
  static const _kSeen = 'capture_inbox_seen_v1';
  static const _kSms = 'capture_sms_enabled';
  static const _kNotif = 'capture_notif_enabled';
  static const _maxSeen = 800;

  CaptureInboxNotifier(this._ref, this._finance, {bool autoLoad = true}) : super(const CaptureInboxState()) {
    if (autoLoad) _load();
  }

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _load() => _loading ??= () async {
        final prefs = await SharedPreferences.getInstance();
        final items = <CaptureItem>[];
        final raw = prefs.getString(_kItems);
        if (raw != null) {
          try {
            for (final j in jsonDecode(raw) as List) {
              final it = CaptureItem.fromJson((j as Map).cast<String, dynamic>());
              if (it != null) items.add(it);
            }
          } catch (_) {}
        }
        state = state.copyWith(
          items: items,
          seen: (prefs.getStringList(_kSeen) ?? const []).toSet(),
          smsEnabled: prefs.getBool(_kSms) ?? false,
          notificationsEnabled: prefs.getBool(_kNotif) ?? false,
        );
        _loaded = true;
      }();

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kItems, jsonEncode(state.items.map((i) => i.toJson()).toList()));
    var seen = state.seen.toList();
    if (seen.length > _maxSeen) seen = seen.sublist(seen.length - _maxSeen);
    await prefs.setStringList(_kSeen, seen);
  }

  Future<void> setSmsEnabled(bool v) async {
    await _load();
    state = state.copyWith(smsEnabled: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSms, v);
    await NativeCaptureBridge.setCaptureEnabled(sms: v, notifications: state.notificationsEnabled);
  }

  Future<void> setNotificationsEnabled(bool v) async {
    await _load();
    state = state.copyWith(notificationsEnabled: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotif, v);
    await NativeCaptureBridge.setCaptureEnabled(sms: state.smsEnabled, notifications: v);
  }

  /// Same payment, same direction, within 10 minutes → same capture (the
  /// SMS and the GPay notification for one UPI payment). A shared bank
  /// reference number is a definitive match.
  static String fingerprint(ParsedTransaction d, DateTime at) {
    if (d.reference != null && d.reference!.length >= 6) return 'ref:${d.reference}';
    final bucket = at.millisecondsSinceEpoch ~/ (10 * 60 * 1000);
    return 'amt:${d.type?.name}:${d.amount?.toStringAsFixed(2)}:$bucket';
  }

  bool _isDuplicateCapture(ParsedTransaction d, DateTime at) {
    final fp = fingerprint(d, at);
    if (state.seen.contains(fp)) return true;
    for (final it in state.items) {
      if (fingerprint(it.draft, it.receivedAt) == fp) return true;
      final sameAmount = it.draft.amount == d.amount && it.draft.type == d.type;
      if (sameAmount && it.receivedAt.difference(at).inMinutes.abs() <= 10) return true;
    }
    return false;
  }

  /// An already-logged transaction this capture most likely is.
  String? _matchLogged(ParsedTransaction d, DateTime at) {
    final when = d.date ?? at;
    for (final t in _finance().transactions) {
      if (t.isDeleted || t.amount != d.amount) continue;
      if (d.type != null && t.type != d.type) continue;
      final day = DateTime(when.year, when.month, when.day);
      final tday = DateTime(t.date.year, t.date.month, t.date.day);
      if (day.difference(tday).inDays.abs() <= 1) return t.id;
    }
    return null;
  }

  /// Adds a parsed draft (from any source). Returns false if it was a
  /// duplicate of something already in / handled by the inbox.
  Future<bool> add(ParsedTransaction draft, CaptureSource source, {DateTime? receivedAt, String? sender}) async {
    await _load();
    if (!draft.hasAmount) return false;
    final at = receivedAt ?? DateTime.now();
    if (_isDuplicateCapture(draft, at)) return false;
    final item = CaptureItem(
      id: const Uuid().v4(),
      source: source,
      receivedAt: at,
      draft: draft,
      sender: sender,
      possibleDuplicateOf: _matchLogged(draft, at),
    );
    state = state.copyWith(items: [item, ...state.items]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt)));
    await _persist();
    return true;
  }

  /// Parses and adds raw native captures; returns how many were new.
  Future<int> ingest(List<RawCapture> raws) async {
    await _load();
    var added = 0;
    final parser = BankMessageParser(_finance());
    for (final r in raws) {
      final d = parser.parse(r.body, receivedAt: r.receivedAt, sender: r.sender);
      if (d == null) continue;
      final src = r.source == 'notification' ? CaptureSource.notification : CaptureSource.sms;
      if (await add(d, src, receivedAt: r.receivedAt, sender: r.sender)) added++;
    }
    return added;
  }

  /// Pulls whatever the native side queued while the app was closed.
  Future<int> syncFromNative() async {
    final raws = await NativeCaptureBridge.drainCaptured();
    if (raws.isEmpty) return 0;
    return ingest(raws);
  }

  /// Manually scans the SMS inbox (Android) — for catching up on the days
  /// before capture was switched on.
  Future<int> scanSmsInbox({int days = 7}) async {
    final raws = await NativeCaptureBridge.scanSmsInbox(days: days);
    return ingest(raws);
  }

  Future<void> _remove(String id) async {
    final it = state.items.where((i) => i.id == id).toList();
    if (it.isEmpty) return;
    state = state.copyWith(
      items: state.items.where((i) => i.id != id).toList(),
      seen: {...state.seen, fingerprint(it.first.draft, it.first.receivedAt)},
    );
    await _persist();
  }

  Future<void> dismiss(String id) => _remove(id);

  /// Called after the user saved the item through the Quick Add sheet.
  Future<void> markLogged(String id) => _remove(id);

  Future<void> clearAll() async {
    state = state.copyWith(
      items: const [],
      seen: {...state.seen, for (final i in state.items) fingerprint(i.draft, i.receivedAt)},
    );
    await _persist();
  }

  /// Logs an item straight into the ledger using its draft + smart defaults.
  /// Returns an error message, or null on success.
  Future<String?> confirm(String id) async {
    final ref = _ref;
    if (ref == null) return 'Unavailable';
    final it = state.items.where((i) => i.id == id).toList();
    if (it.isEmpty) return null;
    final d = it.first.draft;
    final fin = ref.read(financeNotifierProvider);
    final notifier = ref.read(financeNotifierProvider.notifier);
    final type = d.type ?? TransactionType.expense;

    CardModel? card;
    if (d.payCardId != null && d.payCardId != kCashPaySentinel) {
      for (final c in fin.creditCards) {
        if (c.id == d.payCardId && !c.isDeleted) card = c;
      }
    }
    var accountId = d.accountId;
    if (card?.cardType == CardType.debit) accountId = card!.linkedAccountId ?? accountId;
    final accounts = fin.accountsWithCalculatedBalances;
    if (accountId == null || !accounts.any((a) => a.id == accountId)) {
      accountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
    if (accountId == null) return 'Add an account first';

    String? categoryId = d.categoryId;
    final want = type == TransactionType.income ? 'income' : 'expense';
    if (categoryId == null || !fin.categories.any((c) => c.id == categoryId && c.type == want)) {
      final first = fin.categories.where((c) => c.type == want && !c.isDeleted).toList();
      categoryId = first.isEmpty ? null : first.first.id;
    }

    try {
      await notifier.addTransaction(
        accountId: accountId,
        type: type,
        amount: d.amount!,
        categoryId: categoryId,
        merchant: d.merchant,
        date: d.date ?? it.first.receivedAt,
        description: d.notes,
        tags: ['auto-${it.first.source.name}'],
        creditCardId: type == TransactionType.expense ? card?.id : null,
        isCashSpend: type == TransactionType.expense && d.payCardId == kCashPaySentinel,
      );
    } catch (e) {
      debugPrint('CaptureInbox.confirm failed: $e');
      return 'Could not save: $e';
    }
    await _remove(id);
    return null;
  }

  @visibleForTesting
  bool get isLoaded => _loaded;
}

final captureInboxProvider = StateNotifierProvider<CaptureInboxNotifier, CaptureInboxState>((ref) {
  return CaptureInboxNotifier(ref, () => ref.read(financeNotifierProvider));
});
