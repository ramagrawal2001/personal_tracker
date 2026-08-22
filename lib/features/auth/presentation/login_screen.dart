import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/finance_repository.dart';
import '../../../core/services/email_otp_service.dart';
import 'auth_repository.dart';
import 'otp_verification_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _showPass = false;
  bool _sendingOtp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Sign In ────────────────────────────────────────────────────────────────
  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter your email and password');
      return;
    }
    final authNotifier = ref.read(authNotifierProvider.notifier);
    final success = await authNotifier.signIn(email, password);
    if (success && mounted) context.go('/');
  }

  // ── Sign Up → OTP verify ───────────────────────────────────────────────────
  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter your email and password');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    final authNotifier = ref.read(authNotifierProvider.notifier);

    // 1. Create account first
    final success = await authNotifier.signUp(email, password);
    if (!success || !mounted) return;

    // 2. Send OTP
    setState(() => _sendingOtp = true);
    final otpSent = await EmailOtpService.sendOtp(email, purpose: OtpPurpose.verify);
    setState(() => _sendingOtp = false);
    if (!mounted) return;

    if (!otpSent) {
      _showError('Account created but could not send verification email. Please contact support.');
      return;
    }

    // 3. Show OTP screen — push as a page overlay so back keeps state
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          email: email,
          purpose: OtpPurpose.verify,
          onVerified: () async {
            // Clear for new user, then navigate home
            final userId = ref.read(authNotifierProvider).user?.id
                ?? DateTime.now().millisecondsSinceEpoch.toString();
            ref.read(financeNotifierProvider.notifier).clearForNewUser(userId);
            if (mounted) {
              Navigator.pop(context); // pop OTP screen
              context.go('/');
            }
          },
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.expense),
    );
  }

  void _openForgotPassword() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading || _sendingOtp;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background glow orbs
          Positioned(top: -100, left: -50,
            child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.15)))),
          Positioned(bottom: -50, right: -50,
            child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.income.withValues(alpha: 0.10)))),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Branding ──────────────────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 2),
                        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Image.asset('assets/images/app_logo.jpg', width: 90, height: 90, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Aspyric', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  const Text('Your Complete Life Dashboard & Vault', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  const SizedBox(height: 32),

                  // ── Form card ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSignUp ? 'Create Your Account' : 'Sign In to Aspyric',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        if (_isSignUp) ...[
                          const SizedBox(height: 6),
                          const Text('An email verification code will be sent after signup.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                        const SizedBox(height: 18),

                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(LucideIcons.mail, size: 18)),
                        ),
                        const SizedBox(height: 14),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPass,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(LucideIcons.lock, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(_showPass ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: AppColors.textMuted),
                              onPressed: () => setState(() => _showPass = !_showPass),
                            ),
                          ),
                        ),

                        // Forgot password — only in sign-in mode
                        if (!_isSignUp) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                              onPressed: _openForgotPassword,
                              child: const Text('Forgot Password?', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],

                        // Error
                        if (authState.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withValues(alpha: 0.4))),
                            child: Row(children: [
                              const Icon(LucideIcons.alertCircle, color: Colors.redAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(authState.errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                            ]),
                          ),
                        ],

                        const SizedBox(height: 22),

                        // CTA button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : (_isSignUp ? _signUp : _signIn),
                            child: isLoading
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text(_isSignUp ? 'Create Account & Verify' : 'Sign In'),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Toggle sign-up / sign-in
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSignUp ? 'Already registered?' : 'Need a new account?',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                            TextButton(
                              onPressed: () => setState(() { _isSignUp = !_isSignUp; }),
                              child: Text(
                                _isSignUp ? 'Sign In' : 'Register',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        // Legal links
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => context.push('/privacy-policy'),
                              style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                              child: const Text('Privacy Policy', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ),
                            const Text('·', style: TextStyle(color: AppColors.textMuted)),
                            TextButton(
                              onPressed: () => context.push('/terms'),
                              style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                              child: const Text('Terms & Conditions', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
