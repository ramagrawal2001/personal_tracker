import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/email_otp_service.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final OtpPurpose purpose;
  /// Called when OTP is verified successfully
  final Future<void> Function() onVerified;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.purpose,
    required this.onVerified,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _ctrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _foci = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  String? _error;
  int _resendSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 1) { t.cancel(); setState(() => _resendSeconds = 0); }
      else { setState(() => _resendSeconds--); }
    });
  }

  Future<void> _resend() async {
    setState(() { _error = null; _loading = true; });
    final ok = await EmailOtpService.sendOtp(widget.email, purpose: widget.purpose);
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'OTP resent to ${widget.email}' : 'Failed to resend. Try again.'),
        backgroundColor: ok ? AppColors.income : AppColors.expense,
      ));
      if (ok) _startResendTimer();
    }
  }

  String get _enteredOtp => _ctrls.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_enteredOtp.length < 6) {
      setState(() => _error = 'Please enter the complete 6-digit OTP');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final result = await EmailOtpService.verifyOtp(widget.email, _enteredOtp);

    if (result == OtpResult.ok) {
      await widget.onVerified();
    } else {
      setState(() {
        _loading = false;
        _error = result == OtpResult.expired
            ? 'OTP has expired. Please request a new one.'
            : result == OtpResult.notFound
                ? 'No OTP found. Please request a new one.'
                : 'Incorrect OTP. Please try again.';
        // Clear boxes on wrong
        for (final c in _ctrls) { c.clear(); }
        _foci[0].requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrls) { c.dispose(); }
    for (final f in _foci) { f.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReset = widget.purpose == OtpPurpose.resetPassword;
    final hint = EmailOtpService.testHint(widget.email);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Manual back row (no AppBar to avoid double arrow)
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary, size: 20),
                    SizedBox(width: 6),
                    Text('Back', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Header icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isReset ? LucideIcons.keyRound : LucideIcons.mailCheck,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),

            const SizedBox(height: 20),
            Text(
              isReset ? 'Check Your Email' : 'Verify Your Email',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
                children: [
                  const TextSpan(text: 'We sent a 6-digit code to\n'),
                  TextSpan(text: widget.email, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.beaker, color: AppColors.warning, size: 14),
                  const SizedBox(width: 8),
                  Text('Test account $hint', style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            const SizedBox(height: 36),

            // OTP boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) => _OtpBox(
                controller: _ctrls[i],
                focusNode: _foci[i],
                onChanged: (val) {
                  if (val.isNotEmpty && i < 5) _foci[i + 1].requestFocus();
                  if (val.isEmpty && i > 0) _foci[i - 1].requestFocus();
                  if (_enteredOtp.length == 6) _verify();
                },
              )),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.expense.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.expense.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.alertCircle, color: AppColors.expense, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.expense, fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 32),

            // Verify button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Verify OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),

            // Resend
            Center(
              child: _resendSeconds > 0
                  ? Text('Resend OTP in $_resendSeconds seconds', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))
                  : TextButton.icon(
                      onPressed: _loading ? null : _resend,
                      icon: const Icon(LucideIcons.refreshCw, size: 16, color: AppColors.primary),
                      label: const Text('Resend OTP', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onChanged;

  const _OtpBox({required this.controller, required this.focusNode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 58,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
