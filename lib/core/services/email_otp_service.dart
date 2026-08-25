import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env_config.dart';

/// ─── Test-account bypass map ────────────────────────────────────────────────
/// These emails always accept the listed OTP without an actual email being
/// sent — but ONLY in debug builds (`kDebugMode`). Release/profile builds
/// never treat these as special, so this can't be used to skip verification
/// on a shipped app.
const Map<String, String> _testOtps = {
  'test@aspyric.app'  : '123456',
  'test2@aspyric.app' : '123456',
  'demo@aspyric.app'  : '000000',
  'admin@aspyric.app' : '111111',
  'qa@aspyric.app'    : '999999',
  'user@aspyric.app'  : '246810',
};

const _otpTtlSecs   = 300; // 5 minutes
const _maxAttempts  = 5;   // failed guesses allowed per issued OTP

bool _isTestAccount(String normalisedEmail) => kDebugMode && _testOtps.containsKey(normalisedEmail);

class EmailOtpService {
  // ── Generate & send OTP via Resend ───────────────────────────────────────
  static Future<bool> sendOtp(String email, {OtpPurpose purpose = OtpPurpose.verify}) async {
    final normalised = email.trim().toLowerCase();

    // Test-account (debug builds only): skip real send, just store the known OTP
    if (_isTestAccount(normalised)) {
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
          'Authorization': 'Bearer ${EnvConfig.resendApiKey}',
          'Content-Type' : 'application/json',
        },
        body: jsonEncode({
          'from'   : EnvConfig.resendFromEmail,
          'to'     : [email],
          'subject': subject,
          'html'   : body,
        }),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the active OTP stored for this email. Only ever returns a
  /// value for debug-build test accounts or straight from local storage on
  /// the same device that requested it — it does not expose other users'
  /// codes over the network.
  static Future<String?> getLatestOtpForTesting(String email) async {
    final normalised = email.trim().toLowerCase();
    if (_isTestAccount(normalised)) {
      return _testOtps[normalised];
    }
    if (!kDebugMode) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('otp_code_$normalised');
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────
  static Future<OtpResult> verifyOtp(String email, String enteredOtp) async {
    final normalised = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final storedOtp    = prefs.getString('otp_code_$normalised');
    final storedExpiry = prefs.getInt('otp_expiry_$normalised') ?? 0;
    final attemptsKey  = 'otp_attempts_$normalised';
    final attempts     = prefs.getInt(attemptsKey) ?? 0;

    if (storedOtp == null) return OtpResult.notFound;
    if (DateTime.now().millisecondsSinceEpoch > storedExpiry) return OtpResult.expired;
    if (attempts >= _maxAttempts) return OtpResult.tooManyAttempts;

    if (storedOtp.trim() != enteredOtp.trim()) {
      await prefs.setInt(attemptsKey, attempts + 1);
      return OtpResult.wrong;
    }

    // Clear after successful verify
    await prefs.remove('otp_code_$normalised');
    await prefs.remove('otp_expiry_$normalised');
    await prefs.remove(attemptsKey);
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
    await prefs.remove('otp_attempts_$email');
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

  /// Returns test OTP hint for development — empty string outside debug builds
  static String testHint(String email) {
    if (!kDebugMode) return '';
    final normalised = email.trim().toLowerCase();
    return _testOtps[normalised] != null ? '(Test OTP: ${_testOtps[normalised]})' : '';
  }

  static bool isTestAccount(String email) => _isTestAccount(email.trim().toLowerCase());
}

enum OtpPurpose { verify, resetPassword }
enum OtpResult  { ok, wrong, expired, notFound, tooManyAttempts }
