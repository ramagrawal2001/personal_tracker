import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _kBackupKeyStorageKey = 'aspyric_backup_aes_key_v1';
const _backupFileName = 'aspyric_vault_backup.enc';

class BackupService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// A random-per-device AES-256 key, generated once and kept in the
  /// platform Keychain/Keystore. Nothing about backup confidentiality
  /// depends on a value baked into source code.
  static Future<enc.Key> _deviceKey() async {
    final existing = await _secureStorage.read(key: _kBackupKeyStorageKey);
    if (existing != null) {
      return enc.Key.fromBase64(existing);
    }
    final generated = enc.Key.fromSecureRandom(32);
    await _secureStorage.write(key: _kBackupKeyStorageKey, value: generated.base64);
    return generated;
  }

  /// Encrypts [stateJson] with AES-256 (CBC) using a device-held key. The IV
  /// is random per export and stored alongside the ciphertext (as is
  /// standard for CBC); a SHA-256 checksum of the plaintext lets [decrypt]
  /// detect a wrong key or corrupted/tampered payload before returning data.
  static Future<String> exportEncryptedBackup(Map<String, dynamic> stateJson) async {
    final key = await _deviceKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final rawJson = jsonEncode(stateJson);
    final checksum = sha256.convert(utf8.encode(rawJson)).toString();
    final encrypted = encrypter.encrypt(rawJson, iv: iv);

    return jsonEncode({
      'version': '2.0.0',
      'timestamp': DateTime.now().toIso8601String(),
      'checksum': checksum,
      'iv': iv.base64,
      'payload': encrypted.base64,
    });
  }

  /// Decrypts a payload produced by [exportEncryptedBackup]. Returns null if
  /// the payload is malformed, was produced by a different device's key, or
  /// fails its integrity check.
  static Future<Map<String, dynamic>?> importEncryptedBackup(String encryptedString) async {
    try {
      final container = jsonDecode(encryptedString) as Map<String, dynamic>;
      final key = await _deviceKey();
      final iv = enc.IV.fromBase64(container['iv'] as String);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final rawJson = encrypter.decrypt64(container['payload'] as String, iv: iv);
      final checksum = sha256.convert(utf8.encode(rawJson)).toString();
      if (checksum != container['checksum']) {
        return null; // Tampered payload, or decrypted with the wrong key
      }

      return jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _backupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _backupFileName));
  }

  /// Writes an encrypted snapshot to the app's local storage, returning the
  /// file path. This is a device-local vault copy, not a cloud upload — it
  /// protects against accidental in-app data loss, not device loss.
  static Future<String> saveBackupToDisk(Map<String, dynamic> stateJson) async {
    final payload = await exportEncryptedBackup(stateJson);
    final file = await _backupFile();
    await file.writeAsString(payload);
    return file.path;
  }

  /// Reads and decrypts the most recent on-disk backup, if one exists.
  static Future<Map<String, dynamic>?> loadBackupFromDisk() async {
    final file = await _backupFile();
    if (!await file.exists()) return null;
    final payload = await file.readAsString();
    return importEncryptedBackup(payload);
  }

  static Future<bool> hasBackupOnDisk() async {
    final file = await _backupFile();
    return file.exists();
  }
}
