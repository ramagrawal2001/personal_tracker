import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../constants/app_constants.dart';

/// A user-pinned one-tap entry ("Chai ₹20 Cash", "Petrol ₹500 HDFC").
class QuickTemplate {
  final String id;
  final String label;
  final TransactionType type;
  final double? amount;
  final String? merchant;
  final String? categoryId;
  final String? accountId;
  final String? payCardId;

  const QuickTemplate({
    required this.id,
    required this.label,
    required this.type,
    this.amount,
    this.merchant,
    this.categoryId,
    this.accountId,
    this.payCardId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'amount': amount,
        'merchant': merchant,
        'categoryId': categoryId,
        'accountId': accountId,
        'payCardId': payCardId,
      };

  static QuickTemplate? fromJson(Map<String, dynamic> j) {
    try {
      return QuickTemplate(
        id: j['id'] as String,
        label: j['label'] as String,
        type: TransactionType.values.firstWhere((t) => t.name == j['type'], orElse: () => TransactionType.expense),
        amount: (j['amount'] as num?)?.toDouble(),
        merchant: j['merchant'] as String?,
        categoryId: j['categoryId'] as String?,
        accountId: j['accountId'] as String?,
        payCardId: j['payCardId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Device-local list of pinned templates (kept off the cloud schema on
/// purpose — they're a per-phone convenience, like a keyboard shortcut).
class QuickTemplatesNotifier extends StateNotifier<List<QuickTemplate>> {
  static const _k = 'quick_templates_v1';

  QuickTemplatesNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k);
    if (raw == null) return;
    try {
      state = (jsonDecode(raw) as List)
          .map((j) => QuickTemplate.fromJson((j as Map).cast<String, dynamic>()))
          .whereType<QuickTemplate>()
          .toList();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k, jsonEncode(state.map((t) => t.toJson()).toList()));
  }

  Future<void> add({
    required String label,
    required TransactionType type,
    double? amount,
    String? merchant,
    String? categoryId,
    String? accountId,
    String? payCardId,
  }) async {
    state = [
      ...state,
      QuickTemplate(
        id: const Uuid().v4(),
        label: label,
        type: type,
        amount: amount,
        merchant: merchant,
        categoryId: categoryId,
        accountId: accountId,
        payCardId: payCardId,
      ),
    ];
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((t) => t.id != id).toList();
    await _save();
  }
}

final quickTemplatesProvider = StateNotifierProvider<QuickTemplatesNotifier, List<QuickTemplate>>(
  (ref) => QuickTemplatesNotifier(),
);
