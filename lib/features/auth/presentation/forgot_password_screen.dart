import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/email_otp_service.dart';
import 'otp_verification_screen.dart';

enum _ForgotStep { email, otp, newPassword, done }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  _ForgotStep _step = _ForgotStep.email;
  final _emailCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _showPass = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final ok = await EmailOtpService.sendOtp(email, purpose: OtpPurpose.resetPassword);
    setState(() => _loading = false);
    if (!mounted) return;
    if (ok) {
      setState(() => _step = _ForgotStep.otp);
    } else {
      setState(() => _error = 'Could not send OTP. Please check your email and try again.');
    }
  }

  Future<void> _onOtpVerified() async {
    if (mounted) setState(() => _step = _ForgotStep.newPassword);
  }

  Future<void> _resetPassword() async {
    final pass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: pass));
      setState(() { _step = _ForgotStep.done; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Failed to update password. Please try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Forgot Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 17)),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _ForgotStep.email:
        return _buildEmailStep();
      case _ForgotStep.otp:
        return OtpVerificationScreen(
          key: const ValueKey('otp'),
          email: _emailCtrl.text.trim(),
          purpose: OtpPurpose.resetPassword,
          onVerified: _onOtpVerified,
          showBack: false, // Parent Scaffold already has AppBar with back button
        );
      case _ForgotStep.newPassword:
        return _buildNewPasswordStep();
      case _ForgotStep.done:
        return _buildDoneStep();
    }
  }

  Widget _buildEmailStep() => SingleChildScrollView(
    key: const ValueKey('email'),
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(LucideIcons.keyRound, color: AppColors.warning, size: 32),
        ),
        const SizedBox(height: 20),
        Text('Reset Password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text("Enter your registered email. We'll send a verification code to reset your password.", style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5)),
        const SizedBox(height: 32),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            prefixIcon: Icon(LucideIcons.mail, size: 18),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBox(_error!),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendOtp,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Send Reset Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ),
  );

  Widget _buildNewPasswordStep() => SingleChildScrollView(
    key: const ValueKey('newpass'),
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.income.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(LucideIcons.lock, color: AppColors.income, size: 32),
        ),
        const SizedBox(height: 20),
        Text('Set New Password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Create a strong password for your Aspyric account.', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        const SizedBox(height: 32),
        TextField(
          controller: _newPassCtrl,
          obscureText: !_showPass,
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: const Icon(LucideIcons.lock, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_showPass ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: AppColors.textMuted),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPassCtrl,
          obscureText: !_showPass,
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(LucideIcons.lock, size: 18),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorBox(_error!)],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _resetPassword,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ),
  );

  Widget _buildDoneStep() => Center(
    key: const ValueKey('done'),
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.income.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(LucideIcons.checkCircle, color: AppColors.income, size: 56),
          ),
          const SizedBox(height: 24),
          Text('Password Updated!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Text('Your password has been reset successfully. Sign in with your new password.', style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Back to Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorBox(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.expense.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.expense.withValues(alpha: 0.3))),
    child: Row(children: [
      Icon(LucideIcons.alertCircle, color: AppColors.expense, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: TextStyle(color: AppColors.expense, fontSize: 13))),
    ]),
  );
}
