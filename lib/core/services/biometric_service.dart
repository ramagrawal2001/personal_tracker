import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if hardware supports biometrics
  static Future<bool> isBiometricSupported() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      debugPrint('Biometric support error: $e');
      return false;
    }
  }

  /// Trigger Face ID / Fingerprint (or device PIN/pattern, via
  /// `biometricOnly: false`) prompt. Fails **closed**: any error, or a
  /// device with no authentication method configured at all, denies access
  /// rather than silently unlocking. Callers that gate enabling the lock
  /// (e.g. the Biometric Lock toggle) already require a successful
  /// [authenticate] call first, so a device without hardware support simply
  /// can't turn the lock on in the first place.
  static Future<bool> authenticate({String reason = 'Scan Face ID or Fingerprint to unlock Finance OS'}) async {
    try {
      final isSupported = await isBiometricSupported();
      if (!isSupported && !kIsWeb) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric auth platform error: $e');
      return false;
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return false;
    }
  }
}
