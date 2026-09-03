import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

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

    // Delivery goes through the `send-otp` Supabase Edge Function, which holds
    // the Resend key as a server secret — nothing email-related ships in the
    // app binary. The code is still generated / stored / verified on-device.
    if (!SupabaseService.isInitialized) return false;

    final otp = _generateOtp();
    await _storeOtp(normalised, otp);

    try {
      final res = await SupabaseService.client.functions.invoke(
        'send-otp',
        body: {
          'email': normalised,
          'code': otp,
          'purpose': purpose == OtpPurpose.resetPassword ? 'resetPassword' : 'verify',
        },
      );
      final data = res.data;
      final ok = res.status == 200 && (data is! Map || data['ok'] == true);
      if (!ok) {
        // Roll back the stored code so a stale one can't be "verified" offline.
        await _clearOtp(normalised);
      }
      return ok;
    } catch (_) {
      await _clearOtp(normalised);
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

  static Future<void> _clearOtp(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('otp_code_$email');
    await prefs.remove('otp_expiry_$email');
    await prefs.remove('otp_attempts_$email');
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
