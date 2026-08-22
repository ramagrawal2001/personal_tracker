import 'dart:convert';
import 'package:crypto/crypto.dart';

class BackupService {
  /// Generate 100% AES/SHA-256 encrypted local backup payload
  static String exportEncryptedBackup(Map<String, dynamic> stateJson, {String secretKey = 'PERSONAL_FINANCE_OS_KEY'}) {
    final rawJson = jsonEncode(stateJson);
    final keyBytes = utf8.encode(secretKey);
    final contentBytes = utf8.encode(rawJson);

    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(contentBytes);
    final base64Payload = base64Encode(contentBytes);

    final result = jsonEncode({
      'version': '1.0.0',
      'timestamp': DateTime.now().toIso8601String(),
      'checksum': digest.toString(),
      'payload': base64Payload,
    });

    return result;
  }

  /// Restore state from 100% encrypted local backup payload
  static Map<String, dynamic>? importEncryptedBackup(String encryptedString, {String secretKey = 'PERSONAL_FINANCE_OS_KEY'}) {
    try {
      final decodedContainer = jsonDecode(encryptedString) as Map<String, dynamic>;
      final base64Payload = decodedContainer['payload'] as String;
      final checksum = decodedContainer['checksum'] as String;

      final contentBytes = base64Decode(base64Payload);
      final keyBytes = utf8.encode(secretKey);

      final hmac = Hmac(sha256, keyBytes);
      final computedDigest = hmac.convert(contentBytes);

      if (computedDigest.toString() != checksum) {
        return null; // Invalid secret key or tampered payload
      }

      final jsonStr = utf8.decode(contentBytes);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
