import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../database/finance_repository.dart' show appDatabaseProvider;
import '../sync/cloud_mappers.dart';
import 'supabase_service.dart';

/// ─── Secret cipher (transparent per-user field encryption) ───────────────────
///
/// Threat model: the app *operator* — anyone who can read the local SQLite file
/// or browse the Supabase Postgres tables — must not be able to read a user's
/// sensitive fields (full card number, CVV, ATM PIN, full bank account number,
/// IFSC, and later notes). The logged-in *user* sees everything transparently:
/// no extra passphrase, no reveal gate.
///
/// Envelope scheme:
///   * DEK — a random 32-byte Data Encryption Key. Every sensitive field is
///     AES-256-GCM encrypted directly with the DEK (fresh random 12-byte IV,
///     serialised `base64(iv):base64(ciphertext||tag)`). The **device keystore
///     copy of the raw DEK is the source of truth** — once a user has logged in
///     on a device it lives in `flutter_secure_storage` and stays there across
///     password changes / resets, so decryption never breaks silently.
///   * KEK — derived from a secret (login password, previous password, or
///     recovery code) with PBKDF2-HMAC-SHA256, 120 000 iterations, a per-secret
///     random 16-byte salt.
///   * Wrapped DEK — the DEK AES-256-GCM encrypted under a KEK. Two wrapped
///     copies are kept in the cloud `user_settings` row: one under the login
///     password, one under a one-time **recovery code**. These are ONLY for
///     bootstrapping a *new* device; the operator sees only ciphertext.
///
/// Auto-heal rules:
///   * Every `signIn`/`signUp` with a password re-writes the password-wrapped
///     DEK from the cached DEK — so an in-app password change needs nothing
///     special, and an email reset with the device still enrolled just works.
///   * A fresh device after an email reset (cloud wrapper won't open with the
///     new password) falls back to [restoreWithPreviousPassword] or
///     [restoreWithRecoveryCode].
///
/// Data is unrecoverable only if the user loses every logged-in device AND
/// forgets both the old password AND the recovery code.
class SecretCipherService {
  SecretCipherService(this._db);

  final AppDatabase _db;

  static const _kdfIterations = 120000;
  static const _saltLength = 16;
  static const _ivLength = 12;
  static const _dekLength = 32;

  // SyncMeta / cloud `user_settings` keys.
  static const _metaWrappedDek = 'sec_wrapped_dek';
  static const _metaKekSalt = 'sec_kek_salt';
  static const _metaWrappedDekRc = 'sec_wrapped_dek_rc';
  static const _metaRcSalt = 'sec_rc_salt';

  // Device-only (OS keystore) keys.
  static const _dekCacheStorageKey = 'aspyric_secret_dek_v1';
  static const _demoDekStorageKey = 'aspyric_secret_demo_dek_v1';
  static const _recoveryCodeStorageKey = 'aspyric_secret_recovery_v1';
  static const _recoveryPendingStorageKey = 'aspyric_secret_recovery_pending_v1';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final Random _rng = Random.secure();

  /// Process-global plaintext DEK cache. Static so every holder of a
  /// [SecretCipherService] shares one unlocked state.
  static enc.Key? _dekKey;

  static enc.Key? get _dek => _dekKey;

  /// Assigning the DEK also drives [readyListenable] / [needsRecoveryListenable]
  /// so the data notifiers and the recovery-prompt UI react without polling.
  static set _dek(enc.Key? value) {
    _dekKey = value;
    readyListenable.value = value != null;
    if (value != null) needsRecoveryListenable.value = false;
  }

  /// Flips to `true` the instant the in-memory DEK becomes available (login,
  /// signup, keystore restore on a session-restore cold start, or a manual
  /// recovery) and back to `false` on sign-out / user switch. Data notifiers
  /// that mapped encrypted rows while the DEK was still absent listen to this
  /// and re-read from Drift so ciphertext placeholders become plaintext.
  static final ValueNotifier<bool> readyListenable = ValueNotifier<bool>(false);

  /// `true` when the user is authenticated but the DEK could not be opened — a
  /// fresh device after a password change / reset, where the cloud DEK wrapper
  /// is still under the OLD key. The shell watches this to raise the
  /// recovery prompt. Cleared the moment a DEK becomes available.
  static final ValueNotifier<bool> needsRecoveryListenable = ValueNotifier<bool>(false);

  /// Synchronous view of [needsRecoveryListenable].
  static bool get needsRecovery => needsRecoveryListenable.value;

  /// The recovery code from the most recent provisioning, kept in memory until
  /// [takeRecoveryCodeForOneTimeDisplay] consumes it (survives even if the OS
  /// keystore write failed).
  static String? _pendingRecoveryCode;

  /// True once the DEK is available, i.e. sensitive fields can be read/written.
  bool get isReady => _dek != null;

  // ── meta helpers ─────────────────────────────────────────────────────────
  Future<String?> _readMeta(String key) async {
    final row = await (_db.select(_db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeMeta(String key, String value) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion(key: Value(key), value: Value(value)),
        );
  }

  Future<void> _deleteMeta(String key) async {
    await (_db.delete(_db.syncMeta)..where((m) => m.key.equals(key))).go();
  }

  Future<String?> _readStore(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      debugPrint('SecretCipherService: keystore read ($key) failed: $e');
      return null;
    }
  }

  Future<void> _writeStore(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecretCipherService: keystore write ($key) failed: $e');
    }
  }

  Future<void> _deleteStore(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {/* ignore */}
  }

  // ── PBKDF2-HMAC-SHA256 ───────────────────────────────────────────────────
  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int dkLen) {
    final hmac = Hmac(sha256, password);
    final blocks = (dkLen / 32).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blocks; block++) {
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;
      var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return out.toBytes().sublist(0, dkLen);
  }

  static enc.Key _deriveKek(String secret, Uint8List salt) =>
      enc.Key(_pbkdf2(utf8.encode(secret.trim()), salt, _kdfIterations, _dekLength));

  static enc.Encrypter _gcm(enc.Key key) => enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

  // ── envelope (wrap / unwrap the DEK with a KEK) ─────────────────────────
  static String _wrapDek(enc.Key kek, enc.Key dek) {
    final iv = enc.IV.fromSecureRandom(_ivLength);
    return '${iv.base64}:${_gcm(kek).encryptBytes(dek.bytes, iv: iv).base64}';
  }

  static enc.Key? _unwrapDek(enc.Key kek, String blob) {
    final parts = blob.split(':');
    if (parts.length != 2) return null;
    try {
      final iv = enc.IV.fromBase64(parts[0]);
      final bytes = _gcm(kek).decryptBytes(enc.Encrypted.fromBase64(parts[1]), iv: iv);
      if (bytes.length != _dekLength) return null;
      return enc.Key(Uint8List.fromList(bytes));
    } catch (_) {
      return null; // wrong secret / tampered wrapper
    }
  }

  static String _generateRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1
    String group() => List.generate(4, (_) => alphabet[_rng.nextInt(alphabet.length)]).join();
    return '${group()}-${group()}-${group()}-${group()}';
  }

  // ── cloud lookup ─────────────────────────────────────────────────────────
  /// `null` means an actual attempted request to a live Supabase client
  /// failed (offline, timeout, RLS hiccup, anything) — NOT that no wrapper
  /// exists. Callers must never treat that as "safe to provision a fresh
  /// DEK": every sign-out clears the local wrapper copy (see [wipe]), so
  /// this cloud row is the *only* remaining record of the real key on a
  /// device that hits this path — a transient failure here must never be
  /// indistinguishable from "genuinely no wrapper", or a sign-out
  /// immediately followed by a flaky sign-in silently orphans every
  /// already-encrypted field, permanently. An empty map means either the
  /// request definitely succeeded with no row, or there is no cloud at all
  /// for this session (demo/offline/test) — both are cases where "provision
  /// fresh, there's nothing to wait for" is the correct, certain answer.
  Future<Map<String, dynamic>?> _fetchCloudKeyRow(String userId) async {
    if (!SupabaseService.isInitialized) return <String, dynamic>{};
    // A couple of quick retries so a one-off network blip on this
    // particular request — which every sign-out makes the sole remaining
    // record of the real key — doesn't route the caller into "needs
    // recovery" for a problem that would have cleared itself half a second
    // later.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final row = await SupabaseService.client
            .from('user_settings')
            .select('sec_wrapped_dek, sec_kek_salt, sec_wrapped_dek_rc, sec_rc_salt')
            .eq('user_id', userId)
            .maybeSingle();
        if (row == null) return <String, dynamic>{};
        return Map<String, dynamic>.from(row as Map);
      } catch (e) {
        debugPrint('SecretCipherService: cloud key lookup failed (attempt ${attempt + 1}/3): $e');
        if (attempt < 2) await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return null;
  }

  /// Pushes the (now re-wrapped) DEK key material straight to the cloud
  /// `user_settings` row — there is no outbox any more, so this is a direct
  /// upsert instead of an enqueue. Best-effort: a failure here just means the
  /// next settings push (or `refreshFromCloud` adopting a device that *did*
  /// succeed) catches it up; the DEK itself is already safe in this device's
  /// keystore regardless.
  Future<void> _enqueueKeySync(String userId) async {
    try {
      final now = DateTime.now();
      await _writeMeta('settings_updated_at', now.toIso8601String());
      if (!SupabaseService.isInitialized || SupabaseService.client.auth.currentSession == null) return;
      final prefs = await SharedPreferences.getInstance();
      final row = settingsToCloudJson(
        userId,
        emergencyBuffer: prefs.getDouble(kPrefEmergencyBuffer) ?? 20000.0,
        currencySymbol: prefs.getString(kPrefCurrencySymbol) ?? '₹',
        isRoundUpEnabled: prefs.getBool(kPrefRoundUpEnabled) ?? false,
        isAutoBackupEnabled: prefs.getBool(kPrefAutoBackupEnabled) ?? false,
        updatedAt: now,
        secWrappedDek: await _readMeta(_metaWrappedDek),
        secKekSalt: await _readMeta(_metaKekSalt),
        secWrappedDekRc: await _readMeta(_metaWrappedDekRc),
        secRcSalt: await _readMeta(_metaRcSalt),
      );
      await SupabaseService.client.from('user_settings').upsert(row, onConflict: 'user_id');
    } catch (e) {
      debugPrint('SecretCipherService: could not push key sync: $e');
    }
  }

  /// (Re)writes the password-wrapped DEK from the currently-cached DEK. Reuses
  /// the existing salt when present so the wrapper stays stable for an
  /// unchanged password.
  Future<void> _rewrapUnderPassword(String userId, String password) async {
    final dek = _dek;
    if (dek == null) return;
    final existingSalt = await _readMeta(_metaKekSalt);
    final salt = existingSalt != null ? base64Decode(existingSalt) : enc.SecureRandom(_saltLength).bytes;
    if (existingSalt == null) await _writeMeta(_metaKekSalt, base64Encode(salt));
    await _writeMeta(_metaWrappedDek, _wrapDek(_deriveKek(password, salt), dek));
    await _enqueueKeySync(userId);
  }

  Future<String> _provisionNewDek(String userId, String password) async {
    final dek = enc.Key(enc.SecureRandom(_dekLength).bytes);
    _dek = dek;
    await _writeStore(_dekCacheStorageKey, dek.base64);

    final salt = enc.SecureRandom(_saltLength).bytes;
    await _writeMeta(_metaKekSalt, base64Encode(salt));
    await _writeMeta(_metaWrappedDek, _wrapDek(_deriveKek(password, salt), dek));

    final code = _generateRecoveryCode();
    final rcSalt = enc.SecureRandom(_saltLength).bytes;
    await _writeMeta(_metaRcSalt, base64Encode(rcSalt));
    await _writeMeta(_metaWrappedDekRc, _wrapDek(_deriveKek(code, rcSalt), dek));
    await _writeStore(_recoveryCodeStorageKey, code);
    await _writeStore(_recoveryPendingStorageKey, '1');
    _pendingRecoveryCode = code;

    await _enqueueKeySync(userId);
    return code;
  }

  Future<void> _useDemoDek() async {
    await restoreFromCache();
    if (_dek != null) return;
    final existing = await _readStore(_demoDekStorageKey);
    if (existing != null) {
      _dek = enc.Key.fromBase64(existing);
      return;
    }
    final dek = enc.Key(enc.SecureRandom(_dekLength).bytes);
    _dek = dek;
    await _writeStore(_demoDekStorageKey, dek.base64);
  }

  // ── lifecycle (called from AuthNotifier) ────────────────────────────────
  /// Called with the plaintext password in hand right after a successful
  /// sign-in. Restores / unwraps / (first-time) provisions the DEK, then always
  /// refreshes the password-wrapped copy so password changes auto-heal.
  Future<void> onLogin(String userId, String password, {bool isDemo = false}) async {
    await restoreFromCache();

    if (isDemo) {
      if (_dek == null) await _useDemoDek();
      return;
    }

    if (_dek != null) {
      // Device keystore already holds the DEK — that's authoritative. Refresh
      // the cloud password-wrapper (covers an in-app or email password change).
      await _rewrapUnderPassword(userId, password);
      return;
    }

    var wrapped = await _readMeta(_metaWrappedDek);
    var saltB64 = await _readMeta(_metaKekSalt);
    if (wrapped == null || saltB64 == null) {
      final cloud = await _fetchCloudKeyRow(userId);
      if (cloud == null) {
        // Couldn't reach the cloud to check — every sign-out clears the local
        // wrapper copy, so this is the ONLY place a wrapper for an existing
        // account would show up. Treating a failed lookup the same as
        // "confirmed no wrapper" would fall through to provisioning a brand
        // new DEK below and permanently orphan every already-encrypted
        // field. Surface the recovery prompt instead — safe even though the
        // real issue is transient connectivity, not a lost password — and
        // never invent new key material on uncertainty.
        debugPrint('SecretCipherService: cloud key lookup failed for $userId — refusing to provision a new DEK');
        needsRecoveryListenable.value = true;
        return;
      }
      wrapped = cloud['sec_wrapped_dek'] as String?;
      saltB64 = cloud['sec_kek_salt'] as String?;
      if (wrapped != null && saltB64 != null) {
        await _writeMeta(_metaWrappedDek, wrapped);
        await _writeMeta(_metaKekSalt, saltB64);
      }
      final rcWrapped = cloud['sec_wrapped_dek_rc'] as String?;
      final rcSalt = cloud['sec_rc_salt'] as String?;
      if (rcWrapped != null && rcSalt != null) {
        await _writeMeta(_metaWrappedDekRc, rcWrapped);
        await _writeMeta(_metaRcSalt, rcSalt);
      }
    }

    if (wrapped != null && saltB64 != null) {
      final dek = _unwrapDek(_deriveKek(password, base64Decode(saltB64)), wrapped);
      if (dek != null) {
        _dek = dek;
        await _writeStore(_dekCacheStorageKey, dek.base64);
      } else {
        // Fresh device + password no longer matches the wrapper (email reset).
        // Do NOT regenerate — that would orphan every ciphertext. The UI must
        // offer restoreWithPreviousPassword / restoreWithRecoveryCode.
        debugPrint('SecretCipherService: DEK wrapper will not open for $userId');
        needsRecoveryListenable.value = true;
      }
      return;
    }

    // No wrapper anywhere → genuine first login for this user.
    await _provisionNewDek(userId, password);
  }

  /// Fresh account: always provisions a new DEK + recovery code.
  Future<String?> onSignup(String userId, String password) async {
    await restoreFromCache();
    if (_dek != null) {
      await _rewrapUnderPassword(userId, password);
      return null;
    }
    return _provisionNewDek(userId, password);
  }

  /// Re-wraps the current (cached) DEK under a KEK from [newPassword]. Called by
  /// the change-password flow. Returns false if no DEK is available.
  Future<bool> rewrapForPasswordChange(String userId, String newPassword) async {
    if (_dek == null) return false;
    await _deleteMeta(_metaKekSalt); // force a fresh salt for the new password
    await _rewrapUnderPassword(userId, newPassword);
    return true;
  }

  /// Fresh device after an email reset: unwrap with the previous password, then
  /// re-wrap under the current one.
  Future<bool> restoreWithPreviousPassword(
      String userId, String previousPassword, String currentPassword) async {
    final wrapped = await _readMeta(_metaWrappedDek);
    final saltB64 = await _readMeta(_metaKekSalt);
    if (wrapped == null || saltB64 == null) return false;
    final dek = _unwrapDek(_deriveKek(previousPassword, base64Decode(saltB64)), wrapped);
    if (dek == null) return false;
    _dek = dek;
    await _writeStore(_dekCacheStorageKey, dek.base64);
    await rewrapForPasswordChange(userId, currentPassword);
    return true;
  }

  /// Escape hatch: unwrap with the one-time recovery code, then re-wrap under
  /// the current password.
  Future<bool> restoreWithRecoveryCode(
      String userId, String recoveryCode, String currentPassword) async {
    final wrapped = await _readMeta(_metaWrappedDekRc);
    final saltB64 = await _readMeta(_metaRcSalt);
    if (wrapped == null || saltB64 == null) return false;
    final dek = _unwrapDek(_deriveKek(recoveryCode, base64Decode(saltB64)), wrapped);
    if (dek == null) return false;
    _dek = dek;
    await _writeStore(_dekCacheStorageKey, dek.base64);
    await rewrapForPasswordChange(userId, currentPassword);
    return true;
  }

  /// True when a DEK wrapper exists but the DEK is not open — the UI should
  /// prompt for the previous password or the recovery code.
  Future<bool> needsManualRecovery() async {
    if (_dek != null) return false;
    return (await _readMeta(_metaWrappedDek)) != null;
  }

  /// Reloads the DEK from the OS keystore (app relaunch / session restore).
  Future<void> restoreFromCache() async {
    if (_dek != null) return;
    final cached = await _readStore(_dekCacheStorageKey);
    if (cached != null) {
      _dek = enc.Key.fromBase64(cached);
      return;
    }
    final demo = await _readStore(_demoDekStorageKey);
    if (demo != null) {
      _dek = enc.Key.fromBase64(demo);
      return;
    }
    // No device DEK. A password-wrapper in local meta means this user enrolled
    // on another device and this one came up (session restored from prefs)
    // after a password reset — the DEK can only be reopened with the previous
    // password or the recovery code, so surface the recovery prompt.
    if ((await _readMeta(_metaWrappedDek)) != null) {
      needsRecoveryListenable.value = true;
    }
  }

  // ── recovery code display ────────────────────────────────────────────────
  /// Returns the recovery code if one is queued for its one-time reveal, then
  /// clears the "pending" flag. Null otherwise.
  Future<String?> takeRecoveryCodeForOneTimeDisplay() async {
    final pending = _pendingRecoveryCode;
    if (pending != null) {
      _pendingRecoveryCode = null;
      await _deleteStore(_recoveryPendingStorageKey);
      return pending;
    }
    if ((await _readStore(_recoveryPendingStorageKey)) == null) return null;
    await _deleteStore(_recoveryPendingStorageKey);
    return _readStore(_recoveryCodeStorageKey);
  }

  /// The recovery code, if this device still holds it (Settings → "Show
  /// recovery code"). Null on a device that bootstrapped via password/code.
  Future<String?> getRecoveryCode() async =>
      _pendingRecoveryCode ?? await _readStore(_recoveryCodeStorageKey);

  // ── teardown ─────────────────────────────────────────────────────────────
  /// Full teardown for a user switch.
  Future<void> wipe() async {
    _dek = null;
    _pendingRecoveryCode = null;
    await clearCachedDek();
    await _deleteMeta(_metaWrappedDek);
    await _deleteMeta(_metaKekSalt);
    await _deleteMeta(_metaWrappedDekRc);
    await _deleteMeta(_metaRcSalt);
    await _deleteStore(_demoDekStorageKey);
    await _deleteStore(_recoveryCodeStorageKey);
    await _deleteStore(_recoveryPendingStorageKey);
  }

  /// Forgets the in-memory + keystore-cached DEK (sign-out). The cloud wrappers
  /// stay, so the same user re-logging-in on this device restores it.
  static Future<void> clearCachedDek() async {
    _dek = null;
    _pendingRecoveryCode = null;
    needsRecoveryListenable.value = false;
    try {
      await _secureStorage.delete(key: _dekCacheStorageKey);
    } catch (e) {
      debugPrint('SecretCipherService: could not clear cached DEK: $e');
    }
  }

  // ── field crypto ─────────────────────────────────────────────────────────
  /// Encrypts one sensitive field with the DEK. Throws [StateError] if not
  /// ready (callers should check [isReady] and skip capture).
  String encryptField(String plaintext) {
    final dek = _dek;
    if (dek == null) {
      throw StateError('Secret cipher not ready — DEK unavailable');
    }
    final iv = enc.IV.fromSecureRandom(_ivLength);
    return '${iv.base64}:${_gcm(dek).encrypt(plaintext, iv: iv).base64}';
  }

  /// Decrypts one field. Returns null when not ready, the blob is malformed, or
  /// authentication fails (tampered ciphertext / wrong DEK).
  String? decryptField(String? blob) {
    final dek = _dek;
    if (dek == null || blob == null || blob.isEmpty) return null;
    final parts = blob.split(':');
    if (parts.length != 2) return null;
    try {
      final iv = enc.IV.fromBase64(parts[0]);
      return _gcm(dek).decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
    } catch (_) {
      return null;
    }
  }

  /// Static field crypto — for the mapper layer, which has no service instance
  /// but shares the process-global DEK. [encField] returns the plaintext
  /// unchanged when the cipher isn't ready (so data is never lost); [decField]
  /// returns the raw string when it isn't ciphertext this key can open (legacy
  /// plaintext rows, or cipher not ready) so the UI never breaks.
  static bool get ready => _dek != null;

  static String encField(String plaintext) {
    final dek = _dek;
    if (dek == null) return plaintext;
    final iv = enc.IV.fromSecureRandom(_ivLength);
    return '${iv.base64}:${_gcm(dek).encrypt(plaintext, iv: iv).base64}';
  }

  static String decField(String stored) {
    final dek = _dek;
    if (dek == null || stored.isEmpty) return stored;
    final parts = stored.split(':');
    if (parts.length != 2) return stored; // not our ciphertext shape → legacy plaintext
    try {
      final iv = enc.IV.fromBase64(parts[0]);
      return _gcm(dek).decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
    } catch (_) {
      return stored; // wrong key / tampered — don't crash the list
    }
  }

  /// Masks a value for display, keeping the last [visible] characters.
  static String mask(String value, {int visible = 4}) {
    final trimmed = value.replaceAll(' ', '');
    if (trimmed.length <= visible) return '•' * trimmed.length.clamp(1, 8);
    return '•••• ${trimmed.substring(trimmed.length - visible)}';
  }
}

final secretCipherServiceProvider = Provider<SecretCipherService>((ref) {
  return SecretCipherService(ref.watch(appDatabaseProvider));
});
