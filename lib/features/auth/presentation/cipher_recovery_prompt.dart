import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/secret_cipher_service.dart';
import '../../../core/theme/app_colors.dart';

/// Raised after login on a device that is authenticated but whose field-
/// encryption DEK could not be opened — a fresh device after a password change
/// / reset, where the cloud DEK wrapper is still under the OLD key. Until the
/// user supplies their previous password or their recovery code every encrypted
/// card / bank / note field stays locked, so this prompt is shown prominently
/// and is not barrier-dismissable: the only way past without unlocking is the
/// explicit "Skip for now" (the prompt then re-appears on the next launch).
///
/// On success the DEK setter flips [SecretCipherService.readyListenable], which
/// the finance + notes notifiers already listen to and re-read from Drift, so
/// the previously-locked data appears immediately with no extra plumbing here.
class CipherRecoveryPrompt extends ConsumerStatefulWidget {
  final String userId;
  const CipherRecoveryPrompt({super.key, required this.userId});

  static Future<void> show(BuildContext context, {required String userId}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CipherRecoveryPrompt(userId: userId),
    );
  }

  @override
  ConsumerState<CipherRecoveryPrompt> createState() => _CipherRecoveryPromptState();
}

enum _Mode { recoveryCode, previousPassword }

class _CipherRecoveryPromptState extends ConsumerState<CipherRecoveryPrompt> {
  _Mode _mode = _Mode.recoveryCode;
  final _secretCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _secretCtrl.dispose();
    _currentPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final secret = _secretCtrl.text.trim();
    final currentPw = _currentPwCtrl.text;
    if (secret.isEmpty || currentPw.isEmpty) {
      setState(() => _error = 'Enter both fields to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cipher = ref.read(secretCipherServiceProvider);
    bool ok;
    try {
      ok = _mode == _Mode.recoveryCode
          ? await cipher.restoreWithRecoveryCode(widget.userId, secret, currentPw)
          : await cipher.restoreWithPreviousPassword(widget.userId, secret, currentPw);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Encrypted data unlocked on this device.')),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = _mode == _Mode.recoveryCode
          ? 'That recovery code / current password did not work.'
          : 'That previous password / current password did not work.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCode = _mode == _Mode.recoveryCode;
    return AlertDialog(
      icon: Icon(LucideIcons.lock, color: AppColors.primary),
      title: const Text('Unlock your encrypted data'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This device signed in after a password change, so your saved card, '
              'bank and note details are still locked. Enter your '
              '${isCode ? 'recovery code' : 'previous password'} and your current '
              'password to unlock them.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _secretCtrl,
              autocorrect: false,
              enableSuggestions: false,
              obscureText: !isCode,
              textCapitalization:
                  isCode ? TextCapitalization.characters : TextCapitalization.none,
              decoration: InputDecoration(
                labelText: isCode ? 'Recovery code' : 'Previous password',
                hintText: isCode ? 'XXXX-XXXX-XXXX-XXXX' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currentPwCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.expense, fontSize: 12.5)),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _mode = isCode ? _Mode.previousPassword : _Mode.recoveryCode;
                          _secretCtrl.clear();
                          _error = null;
                        }),
                child: Text(isCode
                    ? 'I have my previous password instead'
                    : 'Use my recovery code instead'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Skip for now'),
        ),
        FilledButton(
          onPressed: _busy ? null : _unlock,
          child: _busy
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Unlock'),
        ),
      ],
    );
  }
}
