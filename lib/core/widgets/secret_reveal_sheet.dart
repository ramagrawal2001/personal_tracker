import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/secret_cipher_service.dart';
import '../theme/app_colors.dart';

/// One masked sensitive field with a plain tap-to-show toggle (no biometric —
/// the logged-in user is already trusted; this is display hygiene, not a gate).
class SecretField {
  final String label;
  final String? encBlob;

  /// Shown when hidden and no value can be derived from a fallback.
  final String maskedFallback;

  /// Regroup a revealed value in blocks of 4 (card / account numbers).
  final bool groupDigits;
  const SecretField(this.label, this.encBlob, {this.maskedFallback = '••••', this.groupDigits = false});
}

/// A bottom sheet that shows sensitive card / bank fields masked, with a single
/// "Show" toggle that decrypts them locally with the cached DEK.
class SecretRevealSheet extends ConsumerStatefulWidget {
  final String title;
  final List<SecretField> fields;
  const SecretRevealSheet({super.key, required this.title, required this.fields});

  @override
  ConsumerState<SecretRevealSheet> createState() => _SecretRevealSheetState();
}

class _SecretRevealSheetState extends ConsumerState<SecretRevealSheet> {
  bool _show = false;
  bool _busy = false;
  String? _error;

  Future<void> _toggle() async {
    if (_show) {
      setState(() => _show = false);
      return;
    }
    setState(() => _busy = true);
    final cipher = ref.read(secretCipherServiceProvider);
    if (!cipher.isReady) {
      await cipher.restoreFromCache();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (cipher.isReady) {
        _show = true;
        _error = null;
      } else {
        _error = 'Encrypted details are locked. Sign in again on this device to unlock them.';
      }
    });
  }

  String _group(String v) {
    final digits = v.replaceAll(RegExp(r'\s'), '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cipher = ref.read(secretCipherServiceProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              Icon(LucideIcons.lock, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(widget.title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('End-to-end encrypted. Only your signed-in devices can read these.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          ...widget.fields.map((f) {
            String display = f.maskedFallback;
            if (_show && cipher.isReady) {
              final plain = cipher.decryptField(f.encBlob);
              if (plain != null) display = f.groupDigits ? _group(plain) : plain;
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.label, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        const SizedBox(height: 3),
                        Text(
                          display,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_show && cipher.isReady && f.encBlob != null)
                    IconButton(
                      icon: Icon(LucideIcons.copy, size: 16, color: AppColors.textMuted),
                      tooltip: 'Copy',
                      onPressed: () {
                        final plain = cipher.decryptField(f.encBlob);
                        if (plain != null) {
                          Clipboard.setData(ClipboardData(text: plain));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied — clears from clipboard history on your own'), duration: Duration(seconds: 2)),
                          );
                        }
                      },
                    ),
                ],
              ),
            );
          }),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.expense)),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _toggle,
              style: ElevatedButton.styleFrom(
                backgroundColor: _show ? AppColors.surfaceLight : AppColors.primary,
                foregroundColor: _show ? AppColors.textPrimary : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
              label: Text(_show ? 'Hide' : 'Show', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
