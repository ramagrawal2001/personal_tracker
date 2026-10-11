import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_constants.dart';
import '../../database/finance_repository.dart' show FinanceState;
import '../../../domain/models/models.dart';
import 'entity_resolver.dart';
import 'parsed_transaction.dart';

/// A free-tier-friendly, OpenAI-compatible chat-completions provider.
class AiProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String defaultModel;

  /// Where the user creates a (free) API key.
  final String keyUrl;
  final String note;

  const AiProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.keyUrl,
    required this.note,
  });
}

const kAiPresets = <AiProviderPreset>[
  AiProviderPreset(
    id: 'groq',
    name: 'Groq (free tier)',
    baseUrl: 'https://api.groq.com/openai/v1',
    defaultModel: 'openai/gpt-oss-20b',
    keyUrl: 'https://console.groq.com/keys',
    note: 'Very fast, generous free tier. Recommended.',
  ),
  AiProviderPreset(
    id: 'gemini',
    name: 'Google Gemini (free tier)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.5-flash',
    keyUrl: 'https://aistudio.google.com/apikey',
    note: 'Free tier via Google AI Studio.',
  ),
  AiProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter (free models)',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'meta-llama/llama-3.3-70b-instruct:free',
    keyUrl: 'https://openrouter.ai/keys',
    note: 'Pick any model ending in ":free".',
  ),
  AiProviderPreset(
    id: 'custom',
    name: 'Custom (OpenAI-compatible)',
    baseUrl: 'http://localhost:11434/v1',
    defaultModel: 'llama3.2',
    keyUrl: '',
    note: 'e.g. Ollama / LM Studio on your network.',
  ),
];

class AiConfig {
  final bool enabled;
  final String presetId;
  final String baseUrl;
  final String model;
  final String apiKey;

  const AiConfig({
    required this.enabled,
    required this.presetId,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  /// Usable for requests — a key is optional only for a custom/local server.
  bool get isUsable => enabled && baseUrl.isNotEmpty && model.isNotEmpty && (apiKey.isNotEmpty || presetId == 'custom');

  AiProviderPreset get preset => kAiPresets.firstWhere((p) => p.id == presetId, orElse: () => kAiPresets.first);
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// Understands free-form text (typed, spoken or OCR'd) with a free LLM and
/// maps the answer onto the user's own accounts / cards / categories.
///
/// Privacy: only the text being parsed plus the *names* of accounts, cards
/// and categories are sent — never balances, card numbers or history.
class AiTransactionService {
  AiTransactionService._();

  static const _kEnabled = 'ai_enabled';
  static const _kPreset = 'ai_preset';
  static const _kBaseUrl = 'ai_base_url';
  static const _kModel = 'ai_model';
  static const _kKey = 'ai_api_key';

  /// Optional build-time key (`--dart-define=AI_API_KEY=...`, e.g. from the
  /// gitignored dart_defines.json) used when none was saved in Settings.
  static const _envKey = String.fromEnvironment('AI_API_KEY');

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static AiConfig? _cache;

  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static Future<AiConfig> load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final presetId = prefs.getString(_kPreset) ?? 'groq';
    final preset = kAiPresets.firstWhere((p) => p.id == presetId, orElse: () => kAiPresets.first);
    String key = '';
    try {
      key = await _secure.read(key: _kKey) ?? '';
    } catch (_) {/* keystore unavailable — treat as no key */}
    if (key.isEmpty) key = _envKey;
    _cache = AiConfig(
      enabled: prefs.getBool(_kEnabled) ?? key.isNotEmpty,
      presetId: preset.id,
      baseUrl: prefs.getString(_kBaseUrl) ?? preset.baseUrl,
      model: prefs.getString(_kModel) ?? preset.defaultModel,
      apiKey: key,
    );
    return _cache!;
  }

  static Future<void> save(AiConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, c.enabled);
    await prefs.setString(_kPreset, c.presetId);
    await prefs.setString(_kBaseUrl, c.baseUrl.trim().replaceAll(RegExp(r'/+$'), ''));
    await prefs.setString(_kModel, c.model.trim());
    try {
      if (c.apiKey.trim().isEmpty) {
        await _secure.delete(key: _kKey);
      } else {
        await _secure.write(key: _kKey, value: c.apiKey.trim());
      }
    } catch (e) {
      debugPrint('AiTransactionService.save: secure storage failed: $e');
    }
    _cache = null;
  }

  static Future<bool> isUsable() async => (await load()).isUsable;

  static Map<String, String> _headers(AiConfig c) => {
        'Content-Type': 'application/json',
        if (c.apiKey.isNotEmpty) 'Authorization': 'Bearer ${c.apiKey}',
        if (c.presetId == 'openrouter') 'X-Title': 'Aspyric',
      };

  /// Orders model ids for picking a chat model: drops speech / moderation /
  /// embedding / image models and ranks good, fast instruction models first.
  @visibleForTesting
  static List<String> rankChatModels(List<String> ids) {
    final skip = RegExp(r'whisper|tts|orpheus|playai|guard|embed|moderation|vision-preview|image|imagen|veo|lyria|aqa|audio|transcribe|speech|safeguard', caseSensitive: false);
    int score(String id) {
      final m = id.toLowerCase();
      var s = 0;
      if (m.contains('gpt-oss-120b')) s += 60;
      if (m.contains('gpt-oss-20b')) s += 55;
      if (m.contains('llama-3.3-70b') || m.contains('llama-4')) s += 50;
      if (m.contains('gemini') && m.contains('flash')) s += 50;
      if (m.contains('qwen3') || m.contains('qwen-3')) s += 40;
      if (m.contains('kimi') || m.contains('deepseek')) s += 35;
      if (m.contains('llama')) s += 20;
      if (m.contains('instant') || m.contains('flash-lite')) s += 5;
      if (m.endsWith(':free')) s += 10;
      if (m.contains('preview') || m.contains('exp')) s -= 5;
      return s;
    }

    final kept = ids.where((id) => !skip.hasMatch(id)).toList()
      ..sort((a, b) {
        final c = score(b).compareTo(score(a));
        return c != 0 ? c : a.compareTo(b);
      });
    return kept;
  }

  /// Lists the provider's model ids (also a cheap "is my key valid?" check).
  static Future<List<String>> listModels(AiConfig c) async {
    final client = clientFactory();
    try {
      final res = await client
          .get(Uri.parse('${c.baseUrl}/models'), headers: _headers(c))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw AiException(_errorText(res));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final ids = ((body['data'] as List?) ?? const [])
          .map((m) => (m as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => id.startsWith('models/') ? id.substring(7) : id)
          .toList();
      return rankChatModels(ids);
    } finally {
      client.close();
    }
  }

  static String _errorText(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      final msg = j is Map ? (j['error'] is Map ? j['error']['message'] : j['error'] ?? j['message']) : null;
      if (msg != null) return 'AI error ${res.statusCode}: $msg';
    } catch (_) {}
    return 'AI error ${res.statusCode}';
  }

  /// Sends [text] to the configured model and returns a resolved draft, or
  /// throws [AiException]. Callers merge the result over the offline parse.
  static Future<ParsedTransaction> parseTransaction(
    String text,
    FinanceState state, {
    CaptureSource source = CaptureSource.typed,
    DateTime? now,
  }) async {
    final c = await load();
    if (!c.isUsable) throw AiException('AI is not configured');
    final today = now ?? DateTime.now();

    final accounts = state.accounts.where((a) => !a.isDeleted).map((a) => a.name).toList();
    final cards = state.creditCards
        .where((x) => !x.isDeleted && (x.cardType == CardType.credit || x.cardType == CardType.debit))
        .map((x) => '${x.name} (${x.cardType.name} card)')
        .toList();
    final expenseCats = state.categories.where((x) => !x.isDeleted && x.type == 'expense').map((x) => x.name).toList();
    final incomeCats = state.categories.where((x) => !x.isDeleted && x.type == 'income').map((x) => x.name).toList();

    final kind = switch (source) {
      CaptureSource.voice => 'a voice note transcript (may contain speech-recognition mistakes)',
      CaptureSource.receipt => 'OCR text from a bill, receipt or payment screenshot (noisy)',
      CaptureSource.sms || CaptureSource.notification || CaptureSource.shortcut => 'a bank / UPI alert message',
      _ => 'a short typed note',
    };

    final system = '''You turn $kind into ONE personal-finance transaction for an Indian user (currency INR).
Reply with ONLY a JSON object, no prose:
{"type":"expense"|"income","amount":number|null,"merchant":string|null,"category":string|null,"account":string|null,"pay_with":string|null,"date":"YYYY-MM-DD"|null,"notes":string|null}
Rules:
- amount: the total actually paid/received as a plain number ("2.5k" = 2500, "two hundred" = 200). For receipts use the grand total.
- merchant: the shop, app, person or payer, short and human-readable ("Swiggy", "Ramesh"); null if unknown.
- category: pick EXACTLY one name from the matching list below, or null.
- account: pick EXACTLY one bank account name from the list, or null.
- pay_with: "cash", or EXACTLY one card name from the list, or null when it was a bank/UPI payment.
- date: resolve relative words against today = ${today.toIso8601String().substring(0, 10)}; null if not mentioned.
- notes: anything else useful in a few words, else null.
Expense categories: ${jsonEncode(expenseCats)}
Income categories: ${jsonEncode(incomeCats)}
Bank accounts: ${jsonEncode(accounts)}
Cards: ${jsonEncode(cards)}''';

    final client = clientFactory();
    try {
      final payload = {
        'model': c.model,
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': text},
        ],
        'response_format': {'type': 'json_object'},
      };
      // Debug builds only: what leaves the phone (the API key is a header and
      // is never logged).
      if (kDebugMode) {
        debugPrint('AI ▶ ${c.baseUrl} model=${c.model} source=${source.name}');
        debugPrint('AI ▶ user text: $text');
        debugPrint('AI ▶ context sent: accounts=$accounts cards=$cards '
            'expenseCats=${expenseCats.length} incomeCats=${incomeCats.length}');
      }
      final started = DateTime.now();
      var res = await client
          .post(Uri.parse('${c.baseUrl}/chat/completions'), headers: _headers(c), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 25));
      // Some free models reject response_format — retry once without it.
      if (res.statusCode == 400 && res.body.contains('response_format')) {
        payload.remove('response_format');
        res = await client
            .post(Uri.parse('${c.baseUrl}/chat/completions'), headers: _headers(c), body: jsonEncode(payload))
            .timeout(const Duration(seconds: 25));
      }
      if (res.statusCode != 200) throw AiException(_errorText(res));
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final content = (((body['choices'] as List).first as Map)['message'] as Map)['content']?.toString() ?? '';
      if (kDebugMode) debugPrint('AI ◀ ${DateTime.now().difference(started).inMilliseconds}ms $content');
      final json = extractJson(content);
      if (json == null) throw AiException('AI returned no usable answer');
      return resolve(json, state, rawText: text);
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException('AI request failed: $e');
    } finally {
      client.close();
    }
  }

  /// Pulls the first JSON object out of a model reply (tolerates ```json
  /// fences and chatter around it).
  @visibleForTesting
  static Map<String, dynamic>? extractJson(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(content.substring(start, end + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Maps the model's names back onto real ids.
  @visibleForTesting
  static ParsedTransaction resolve(Map<String, dynamic> j, FinanceState state, {String? rawText}) {
    String? str(String k) {
      final v = j[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
    }

    final type = str('type')?.toLowerCase() == 'income' ? TransactionType.income : TransactionType.expense;
    final amountRaw = j['amount'];
    final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse(amountRaw?.toString().replaceAll(RegExp(r'[^\d.]'), '') ?? '');

    String? categoryId;
    final cat = str('category')?.toLowerCase();
    if (cat != null) {
      final want = type == TransactionType.income ? 'income' : 'expense';
      for (final c in state.categories) {
        if (!c.isDeleted && c.type == want && c.name.toLowerCase() == cat) categoryId = c.id;
      }
    }

    final resolver = EntityResolver(state);
    String? accountId;
    String? payCardId;
    final acc = str('account');
    if (acc != null) {
      for (final a in state.accounts) {
        if (!a.isDeleted && a.name.toLowerCase() == acc.toLowerCase()) accountId = a.id;
      }
      accountId ??= resolver.fromText(acc).accountId;
    }
    final pay = str('pay_with');
    if (type == TransactionType.expense && pay != null) {
      if (pay.toLowerCase() == 'cash') {
        final c = resolver.cash();
        payCardId = c.payCardId;
        accountId = c.accountId ?? accountId;
      } else {
        final cardName = pay.replaceAll(RegExp(r'\s*\((credit|debit) card\)\s*$', caseSensitive: false), '').toLowerCase();
        for (final card in state.creditCards) {
          if (!card.isDeleted && card.name.toLowerCase() == cardName) {
            payCardId = card.id;
            if (card.cardType == CardType.debit) accountId = card.linkedAccountId ?? accountId;
          }
        }
        if (payCardId == null) {
          final r = resolver.fromText('$pay card');
          payCardId = r.payCardId;
          accountId ??= r.accountId;
        }
      }
    }

    final date = str('date') == null ? null : DateTime.tryParse(str('date')!);
    return ParsedTransaction(
      type: type,
      amount: amount != null && amount > 0 ? amount : null,
      merchant: str('merchant'),
      categoryId: categoryId,
      accountId: accountId,
      payCardId: payCardId,
      date: date == null ? null : DateTime(date.year, date.month, date.day),
      notes: str('notes'),
      rawText: rawText,
    );
  }
}
