import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/database/finance_repository.dart';
import '../../../core/services/smart_entry/native_capture_bridge.dart';
import '../../../core/services/smart_entry/parsed_transaction.dart';
import '../../../core/services/smart_entry/smart_entry.dart';
import '../../../core/theme/app_colors.dart';

/// "Type, speak or scan" bar at the top of Quick Add. Calls [onParsed] with a
/// draft the sheet then pre-fills (only the fields that were found).
class SmartEntryBar extends ConsumerStatefulWidget {
  final void Function(ParsedTransaction draft, {required bool usedAi, required CaptureSource source}) onParsed;
  final bool aiAvailable;

  const SmartEntryBar({super.key, required this.onParsed, this.aiAvailable = false});

  @override
  ConsumerState<SmartEntryBar> createState() => SmartEntryBarState();
}

class SmartEntryBarState extends ConsumerState<SmartEntryBar> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String text, CaptureSource source) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _status = widget.aiAvailable ? 'Understanding with AI…' : null;
    });
    final res = await SmartEntry.fromText(text, ref.read(financeNotifierProvider), source: source);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = res.aiError != null ? 'AI unavailable — used offline parsing' : null;
    });
    if (!res.draft.hasAmount && res.draft.merchant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't find an amount — try \"450 swiggy hdfc\""), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    widget.onParsed(res.draft, usedAi: res.usedAi, source: source);
  }

  Future<void> startVoice() async {
    final transcript = await VoiceEntrySheet.show(context);
    if (transcript == null || transcript.trim().isEmpty || !mounted) return;
    _controller.text = transcript;
    await _run(transcript, CaptureSource.voice);
  }

  Future<void> startScan() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(LucideIcons.camera, color: AppColors.primary),
            title: Text('Take a photo of the bill', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: Icon(LucideIcons.image, color: AppColors.primary),
            title: Text('Pick a receipt / UPI screenshot', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 90);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open ${source == ImageSource.camera ? 'camera' : 'photos'}: $e')));
      }
      return;
    }
    if (file == null || !mounted) return;
    await scanImagePath(file.path);
  }

  /// OCRs an image on-device, then parses it like any other text.
  Future<void> scanImagePath(String path) async {
    setState(() {
      _busy = true;
      _status = 'Reading the image…';
    });
    final text = await NativeCaptureBridge.recognizeText(path);
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() {
        _busy = false;
        _status = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text found in that image'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await _run(text, CaptureSource.receipt);
  }

  /// Parses text handed in from outside (shared text, Shortcuts link).
  Future<void> parseExternal(String text, CaptureSource source) async {
    _controller.text = text.length > 120 ? '${text.substring(0, 117)}…' : text;
    await _run(text, source);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(widget.aiAvailable ? LucideIcons.sparkles : LucideIcons.wand2, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('smart_entry_field'),
                  controller: _controller,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Type it: 450 zomato hdfc yesterday',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (t) => _run(t, CaptureSource.typed),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                IconButton(
                  key: const Key('smart_entry_go'),
                  tooltip: 'Fill the form from this text',
                  icon: Icon(LucideIcons.cornerDownLeft, size: 18, color: AppColors.primary),
                  onPressed: () => _run(_controller.text, CaptureSource.typed),
                ),
                IconButton(
                  key: const Key('smart_entry_mic'),
                  tooltip: 'Say it',
                  icon: Icon(LucideIcons.mic, size: 18, color: AppColors.primary),
                  onPressed: startVoice,
                ),
                IconButton(
                  key: const Key('smart_entry_scan'),
                  tooltip: 'Scan a receipt or payment screenshot',
                  icon: Icon(LucideIcons.scanLine, size: 18, color: AppColors.primary),
                  onPressed: startScan,
                ),
              ],
            ],
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_status!, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
      ],
    );
  }
}

/// Full-screen-ish listening sheet. Uses the phone's own speech recogniser
/// (free, works offline on most devices) and returns the final transcript.
class VoiceEntrySheet extends StatefulWidget {
  const VoiceEntrySheet({super.key});

  static Future<String?> show(BuildContext context) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => const VoiceEntrySheet(),
      );

  @override
  State<VoiceEntrySheet> createState() => _VoiceEntrySheetState();
}

class _VoiceEntrySheetState extends State<VoiceEntrySheet> {
  static final SpeechToText _speech = SpeechToText();
  static bool? _available;
  String _words = '';
  String? _error;
  bool _listening = false;
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    _speech.stop();
    _typed.dispose();
    super.dispose();
  }

  /// The open sheet — the recogniser is a singleton initialised once, so its
  /// callbacks route to whichever sheet is currently showing.
  static _VoiceEntrySheetState? _current;

  static void _onError(String msg) {
    final s = _current;
    if (s == null || !s.mounted) return;
    s.setState(() {
      s._listening = false;
      if (msg != 'error_no_match' || s._words.isEmpty) {
        s._error = msg == 'error_no_match' ? "Didn't catch that — tap the mic and try again" : 'Speech error: $msg';
      }
    });
  }

  static void _onStatus(String status) {
    final s = _current;
    if (s == null || !s.mounted) return;
    if (status == 'done' || status == 'notListening') s.setState(() => s._listening = false);
  }

  Future<void> _start() async {
    _current = this;
    try {
      // Retry when it failed before — the user may have granted the
      // microphone / speech permission in Settings since.
      if (_available != true) {
        _available = await _speech.initialize(
          onError: (e) => _onError(e.errorMsg),
          onStatus: _onStatus,
        );
      }
    } catch (e) {
      _available = false;
    }
    if (!mounted) return;
    if (_available != true) {
      setState(() => _error = 'Voice recognition is not available on this device. Type it below instead.');
      return;
    }
    String? locale;
    try {
      final locales = await _speech.locales();
      // Indian English handles "₹", lakh and Indian merchant names best.
      for (final l in locales) {
        if (l.localeId.toLowerCase().replaceAll('-', '_') == 'en_in') locale = l.localeId;
      }
    } catch (_) {}
    setState(() {
      _error = null;
      _listening = true;
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _words = r.recognizedWords);
        if (r.finalResult && _words.trim().isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) Navigator.pop(context, _words);
          });
        }
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: locale,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_listening ? 'Listening…' : 'Voice entry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Say something like "two hundred on petrol with HDFC card"',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _listening ? () => _speech.stop() : _start,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _listening ? 96 : 80,
              height: _listening ? 96 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _listening ? AppColors.expense : AppColors.primary,
                boxShadow: [
                  if (_listening) BoxShadow(color: AppColors.expense.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4),
                ],
              ),
              child: Icon(_listening ? LucideIcons.square : LucideIcons.mic, color: Colors.white, size: 34),
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Text(
              _words.isEmpty ? (_error ?? '') : '"$_words"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _words.isEmpty ? 13 : 17, color: _words.isEmpty ? AppColors.textMuted : AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          if (_words.isNotEmpty && !_listening)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: () => Navigator.pop(context, _words), child: const Text('Use this')),
            ),
          if (_error != null && _words.isEmpty) ...[
            TextField(
              controller: _typed,
              decoration: const InputDecoration(hintText: '450 swiggy hdfc card'),
              onSubmitted: (t) => Navigator.pop(context, t),
            ),
          ],
        ],
      ),
    );
  }
}
