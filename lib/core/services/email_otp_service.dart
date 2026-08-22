import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ─── Test-account bypass map ────────────────────────────────────────────────
/// These emails always accept the listed OTP without an actual email being sent.
const Map<String, String> _testOtps = {
  'test@aspyric.app'  : '123456',
  'demo@aspyric.app'  : '000000',
  'admin@aspyric.app' : '111111',
  'qa@aspyric.app'    : '999999',
  'user@aspyric.app'  : '246810',
};

const _resendApiKey = 're_MuZoZgT6_KMF1wRuJJZus6bDKbMDuVq7Y';
const _fromEmail    = 'Aspyric <onboarding@resend.dev>';
const _otpTtlSecs   = 300; // 5 minutes

class EmailOtpService {
  // ── Generate & send OTP ──────────────────────────────────────────────────
  static Future<bool> sendOtp(String email, {OtpPurpose purpose = OtpPurpose.verify}) async {
    final normalised = email.trim().toLowerCase();

    // Test-account: skip real send, just store the known OTP
    if (_testOtps.containsKey(normalised)) {
      await _storeOtp(normalised, _testOtps[normalised]!);
      return true;
    }

    final otp = _generateOtp();
    await _storeOtp(normalised, otp);

    try {
      final subject = purpose == OtpPurpose.verify
          ? 'Aspyric — Verify your email'
          : 'Aspyric — Reset your password';
      final body = _buildEmailHtml(otp, purpose);

      final resp = await http.post(
        Uri.parse('https://api.resend.com/emails'),
        headers: {
          'Authorization': 'Bearer $_resendApiKey',
          'Content-Type' : 'application/json',
        },
        body: jsonEncode({
          'from'   : _fromEmail,
          'to'     : [email],
          'subject': subject,
          'html'   : body,
        }),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────
  static Future<OtpResult> verifyOtp(String email, String enteredOtp) async {
    final normalised = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final storedOtp    = prefs.getString('otp_code_$normalised');
    final storedExpiry = prefs.getInt('otp_expiry_$normalised') ?? 0;

    if (storedOtp == null) return OtpResult.notFound;
    if (DateTime.now().millisecondsSinceEpoch > storedExpiry) return OtpResult.expired;
    if (storedOtp.trim() != enteredOtp.trim()) return OtpResult.wrong;

    // Clear after successful verify
    await prefs.remove('otp_code_$normalised');
    await prefs.remove('otp_expiry_$normalised');
    return OtpResult.ok;
  }

  // ── Internal helpers ──────────────────────────────────────────────────────
  static String _generateOtp() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  static Future<void> _storeOtp(String email, String otp) async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().millisecondsSinceEpoch + (_otpTtlSecs * 1000);
    await prefs.setString('otp_code_$email', otp);
    await prefs.setInt('otp_expiry_$email', expiry);
  }

  static String _buildEmailHtml(String otp, OtpPurpose purpose) {
    final purposeText = purpose == OtpPurpose.verify
        ? 'verify your email address'
        : 'reset your password';
    return '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Inter,sans-serif;background:#0F1324;color:#E8EAFB;margin:0;padding:40px 0;">
  <div style="max-width:480px;margin:0 auto;background:#1A1F3A;border-radius:20px;border:1px solid #2D3561;padding:40px;">
    <div style="text-align:center;margin-bottom:28px;">
      <h1 style="color:#6C63FF;font-size:28px;margin:0;letter-spacing:-0.5px;">Aspyric</h1>
      <p style="color:#8B92B8;margin:8px 0 0;font-size:14px;">Your Complete Financial Dashboard</p>
    </div>
    <h2 style="color:#E8EAFB;font-size:20px;margin:0 0 12px;">Your Verification Code</h2>
    <p style="color:#8B92B8;font-size:14px;line-height:1.6;margin:0 0 28px;">
      Use the code below to $purposeText on Aspyric. This code expires in <strong style="color:#E8EAFB;">5 minutes</strong>.
    </p>
    <div style="background:#0F1324;border-radius:16px;border:2px solid #6C63FF;padding:24px;text-align:center;margin-bottom:28px;">
      <span style="font-size:42px;font-weight:bold;letter-spacing:14px;color:#6C63FF;font-family:monospace;">$otp</span>
    </div>
    <p style="color:#5A6180;font-size:12px;line-height:1.6;margin:0;">
      If you did not request this, you can safely ignore this email.<br>
      Never share this code with anyone.
    </p>
    <hr style="border:none;border-top:1px solid #2D3561;margin:24px 0;">
    <p style="color:#5A6180;font-size:11px;text-align:center;margin:0;">© 2026 Aspyric · support@aspyric.app</p>
  </div>
</body>
</html>''';
  }

  /// Returns test OTP hint for development — empty string in prod
  static String testHint(String email) {
    final normalised = email.trim().toLowerCase();
    return _testOtps[normalised] != null ? '(Test OTP: ${_testOtps[normalised]})' : '';
  }

  static bool isTestAccount(String email) => _testOtps.containsKey(email.trim().toLowerCase());
}

enum OtpPurpose { verify, resetPassword }
enum OtpResult  { ok, wrong, expired, notFound }
