import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';

/// Wraps the app and shows a biometric prompt if biometric lock is enabled.
/// Once authenticated, the gated child is displayed.
class BiometricGate extends ConsumerStatefulWidget {
  final Widget child;
  const BiometricGate({super.key, required this.child});

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _checking = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Run check after first frame so providers are initialised
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock when app goes to background and biometric is enabled
    if (state == AppLifecycleState.paused) {
      final bioEnabled = ref.read(financeNotifierProvider).isBiometricEnabled;
      if (bioEnabled) {
        setState(() {
          _unlocked = false;
          _failed = false;
        });
      }
    }
    if (state == AppLifecycleState.resumed && !_unlocked) {
      _check();
    }
  }

  Future<void> _check() async {
    final bioEnabled = ref.read(financeNotifierProvider).isBiometricEnabled;
    if (!bioEnabled) {
      setState(() => _unlocked = true);
      return;
    }
    if (_checking) return;
    setState(() {
      _checking = true;
      _failed = false;
    });
    final ok = await BiometricService.authenticate(
      reason: 'Unlock Aspyric with Face ID or Fingerprint',
    );
    if (mounted) {
      setState(() {
        _unlocked = ok;
        _failed = !ok;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bioEnabled = ref.watch(financeNotifierProvider).isBiometricEnabled;

    // If biometric not enabled, pass straight through
    if (!bioEnabled || _unlocked) return widget.child;

    // Lock screen
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: const Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 56),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Aspyric',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  _failed
                      ? 'Authentication failed. Try again.'
                      : 'Unlock with Face ID or Fingerprint',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _failed ? AppColors.expense : AppColors.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                if (_checking)
                  const CircularProgressIndicator(color: AppColors.primary)
                else
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(LucideIcons.fingerprint, color: Colors.white, size: 20),
                          label: const Text('Unlock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          onPressed: _check,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
