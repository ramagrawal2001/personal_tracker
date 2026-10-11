import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/smart_entry/ai_transaction_service.dart';
import '../../../core/services/smart_entry/capture_inbox.dart';
import '../../../core/services/smart_entry/native_capture_bridge.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/section_header.dart';

/// Settings → Smart logging: free AI provider, auto-capture (Android SMS +
/// payment notifications), and the quick-access entry points.
class SmartLoggingSettingsScreen extends ConsumerStatefulWidget {
  const SmartLoggingSettingsScreen({super.key});

  @override
  ConsumerState<SmartLoggingSettingsScreen> createState() => _SmartLoggingSettingsScreenState();
}

class _SmartLoggingSettingsScreenState extends ConsumerState<SmartLoggingSettingsScreen> with WidgetsBindingObserver {
  AiConfig? _ai;
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  List<String> _models = const [];
  bool _notifAccess = false;
  bool _smsPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system "Notification access" page.
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _load() async {
    final c = await AiTransactionService.load();
    await _refreshPermissions();
    if (!mounted) return;
    setState(() {
      _ai = c;
      _keyCtrl.text = c.apiKey;
      _modelCtrl.text = c.model;
      _urlCtrl.text = c.baseUrl;
    });
  }

  Future<void> _refreshPermissions() async {
    final access = await NativeCaptureBridge.notificationAccessEnabled();
    final sms = await NativeCaptureBridge.hasSmsPermission();
    if (!mounted) return;
    setState(() {
      _notifAccess = access;
      _smsPermission = sms;
    });
    final inbox = ref.read(captureInboxProvider.notifier);
    final s = ref.read(captureInboxProvider);
    // Permission revoked in system settings → reflect it in the switches.
    if (s.notificationsEnabled && !access) await inbox.setNotificationsEnabled(false);
    if (s.smsEnabled && !sms) await inbox.setSmsEnabled(false);
  }

  AiConfig _current({bool? enabled, String? presetId}) => AiConfig(
        enabled: enabled ?? _ai?.enabled ?? false,
        presetId: presetId ?? _ai?.presetId ?? 'groq',
        baseUrl: _urlCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
      );

  Future<void> _saveAi({bool? enabled}) async {
    final c = _current(enabled: enabled);
    await AiTransactionService.save(c);
    final fresh = await AiTransactionService.load();
    if (mounted) setState(() => _ai = fresh);
  }

  Future<void> _pickPreset(String id) async {
    final p = kAiPresets.firstWhere((x) => x.id == id);
    setState(() {
      _urlCtrl.text = p.baseUrl;
      _modelCtrl.text = p.defaultModel;
      _models = const [];
      _testResult = null;
      _ai = _current(presetId: id);
    });
    await _saveAi();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    await _saveAi(enabled: true);
    final c = _current(enabled: true);
    try {
      final models = await AiTransactionService.listModels(c);
      if (!mounted) return;
      setState(() {
        _models = models;
        _testOk = true;
        _testResult = models.contains(c.model) || models.isEmpty
            ? 'Connected ✓ — ${models.length} models available'
            : 'Connected ✓ — but "${c.model}" isn\'t listed. Pick a model below.';
      });
    } catch (e) {
      // Don't leave AI "on" with a key that can't work.
      if (_keyCtrl.text.trim().isEmpty && _ai?.presetId != 'custom') await _saveAi(enabled: false);
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _toggleSms(bool v) async {
    final inbox = ref.read(captureInboxProvider.notifier);
    if (v && !await NativeCaptureBridge.requestSmsPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied — enable it in system settings to use SMS capture'), behavior: SnackBarBehavior.floating),
        );
      }
      await _refreshPermissions();
      return;
    }
    await inbox.setSmsEnabled(v);
    await _refreshPermissions();
    if (v && mounted) {
      final added = await inbox.scanSmsInbox(days: 3);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SMS capture on${added > 0 ? ' — found $added recent transaction${added == 1 ? '' : 's'} to review' : ''}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleNotif(bool v) async {
    final inbox = ref.read(captureInboxProvider.notifier);
    if (v && !_notifAccess) {
      await inbox.setNotificationsEnabled(true);
      await NativeCaptureBridge.openNotificationAccessSettings();
      return; // re-checked on resume
    }
    await inbox.setNotificationsEnabled(v);
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _row({required IconData icon, required Color color, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: AppDecorations.iconBadge(color),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(captureInboxProvider);
    final ai = _ai;
    final preset = ai?.preset ?? kAiPresets.first;

    return AppScaffold(
      title: 'Smart Logging',
      showBackButton: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          // ── AI ────────────────────────────────────────────────────────
          const SectionLabel(label: 'Free AI (voice, text & receipts)'),
          AppCard(
            child: ai == null
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Use AI to understand entries', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                        'Without AI, entries are still parsed on your phone (offline). AI handles messy speech, receipts and unusual SMS better.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      value: ai.enabled,
                      activeColor: AppColors.primary,
                      onChanged: (v) => _saveAi(enabled: v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: ai.presetId,
                      dropdownColor: AppColors.surface,
                      decoration: const InputDecoration(labelText: 'Provider'),
                      items: [for (final p in kAiPresets) DropdownMenuItem(value: p.id, child: Text(p.name))],
                      onChanged: (v) => v == null ? null : _pickPreset(v),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(preset.note, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyCtrl,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: ai.presetId == 'custom' ? 'API key (optional)' : 'API key',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onChanged: (_) => _testResult = null,
                      onEditingComplete: () => _saveAi(),
                    ),
                    if (preset.keyUrl.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _open(preset.keyUrl),
                        icon: Icon(LucideIcons.externalLink, size: 14, color: AppColors.primary),
                        label: Text('Get a free key', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                      ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _modelCtrl,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Model'),
                      onEditingComplete: () => _saveAi(),
                    ),
                    if (_models.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final m in _models.take(40))
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(m, style: const TextStyle(fontSize: 11)),
                                  selected: m == _modelCtrl.text,
                                  onSelected: (_) {
                                    setState(() => _modelCtrl.text = m);
                                    _saveAi();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (ai.presetId == 'custom') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlCtrl,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Base URL (OpenAI-compatible)'),
                        onEditingComplete: () => _saveAi(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      ElevatedButton.icon(
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.plugZap, size: 16),
                        label: const Text('Save & test'),
                      ),
                    ]),
                    if (_testResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_testResult!, style: TextStyle(fontSize: 12, color: _testOk ? AppColors.income : AppColors.expense)),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      'Privacy: only the text being parsed plus the names of your accounts, cards and categories are sent — never balances, card numbers or your history. Voice is transcribed on your phone.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ]),
          ),
          const SizedBox(height: 18),

          // ── Auto-capture ──────────────────────────────────────────────
          const SectionLabel(label: 'Auto-capture'),
          if (NativeCaptureBridge.isAndroid)
            AppCard(
              child: Column(children: [
                SwitchListTile(
                  key: const Key('sms_capture_switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.primary),
                    child: Icon(LucideIcons.messageSquare, color: AppColors.primary, size: 18),
                  ),
                  title: Text('Bank SMS', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    _smsPermission || !inbox.smsEnabled
                        ? 'Debit / credit / card-spend SMS go to the Review Inbox. Read on-device only.'
                        : 'Needs SMS permission',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  value: inbox.smsEnabled && _smsPermission,
                  activeColor: AppColors.primary,
                  onChanged: _toggleSms,
                ),
                Divider(color: AppColors.border, height: 1),
                SwitchListTile(
                  key: const Key('notif_capture_switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: AppDecorations.iconBadge(AppColors.income),
                    child: Icon(LucideIcons.bellRing, color: AppColors.income, size: 18),
                  ),
                  title: Text('Payment-app notifications', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    inbox.notificationsEnabled && !_notifAccess
                        ? 'Allow "Aspyric payment capture" in the screen that opened, then come back'
                        : 'GPay, PhonePe, Paytm, bank apps — catches UPI payments that send no SMS. Only money notifications are read.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  value: inbox.notificationsEnabled && _notifAccess,
                  activeColor: AppColors.primary,
                  onChanged: _toggleNotif,
                ),
                Divider(color: AppColors.border, height: 1),
                _row(
                  icon: LucideIcons.history,
                  color: AppColors.accent,
                  title: 'Scan last 7 days of SMS',
                  subtitle: 'Catch up on payments made before capture was on',
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
                  onTap: () async {
                    if (!await NativeCaptureBridge.requestSmsPermission()) return;
                    final n = await ref.read(captureInboxProvider.notifier).scanSmsInbox(days: 7);
                    await _refreshPermissions();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(n == 0 ? 'Nothing new found' : '$n transaction${n == 1 ? '' : 's'} added to the Review Inbox'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              ]),
            )
          else
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _row(
                  icon: LucideIcons.smartphone,
                  color: AppColors.primary,
                  title: 'iPhone: bank SMS via Shortcuts',
                  subtitle: 'iOS doesn\'t let apps read SMS, but a Shortcuts automation can forward them to Aspyric\'s Review Inbox.',
                ),
                const SizedBox(height: 4),
                Text(
                  '1. Shortcuts app → Automation → + → Message\n'
                  '2. "Message contains": debited  (add another automation for "credited")\n'
                  '3. Run Immediately → New Blank Automation\n'
                  '4. Add action "URL" with the text below, insert the "Message" variable at the end\n'
                  '5. Add action "Open URLs"',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 10),
                _CopyBox(text: 'aspyric://capture?source=shortcut&text='),
                const SizedBox(height: 6),
                Text('Shortcuts URL-encodes the message for you.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
          const SizedBox(height: 18),

          // ── Quick access ──────────────────────────────────────────────
          const SectionLabel(label: 'Log without opening the app'),
          AppCard(
            child: Column(children: [
              if (NativeCaptureBridge.isAndroid) ...[
                _row(
                  icon: LucideIcons.layoutGrid,
                  color: AppColors.primary,
                  title: 'Home-screen widget',
                  subtitle: 'Today\'s spend + Expense / Income / Voice / Scan buttons',
                  trailing: TextButton(
                    onPressed: () async {
                      final ok = await NativeCaptureBridge.requestPinWidget();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Long-press your home screen → Widgets → Aspyric Quick Add'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
                    child: const Text('Add'),
                  ),
                ),
                Divider(color: AppColors.border, height: 1),
                _row(
                  icon: LucideIcons.toggleRight,
                  color: AppColors.accent,
                  title: 'Quick-settings tile',
                  subtitle: 'Swipe down → "Log expense"',
                  trailing: TextButton(
                    onPressed: () async {
                      final ok = await NativeCaptureBridge.requestAddTile();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Swipe down twice → edit (pencil) → drag "Log expense" into your tiles'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
                    child: const Text('Add'),
                  ),
                ),
                Divider(color: AppColors.border, height: 1),
                _row(
                  icon: LucideIcons.share2,
                  color: AppColors.income,
                  title: 'Share to Aspyric',
                  subtitle: 'Share an SMS, UPI receipt or bill photo → "Log in Aspyric"',
                ),
                Divider(color: AppColors.border, height: 1),
              ],
              _row(
                icon: LucideIcons.pointer,
                color: AppColors.warning,
                title: 'App-icon shortcuts',
                subtitle: 'Long-press the Aspyric icon → Add expense / income, Voice entry, Scan receipt',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CopyBox extends StatelessWidget {
  final String text;
  const _CopyBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Expanded(child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textPrimary))),
        IconButton(
          icon: Icon(LucideIcons.copy, size: 16, color: AppColors.primary),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), behavior: SnackBarBehavior.floating));
          },
        ),
      ]),
    );
  }
}
