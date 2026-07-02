import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../constants/storage.dart';
import '../db/db_helper.dart';

/// Coordinates secure storage, biometric authentication, and data purging.
class SecurityService {
  SecurityService._();

  static final SecurityService _instance = SecurityService._();
  static SecurityService? _testOverride;

  /// Singleton accessor.
  factory SecurityService() => _testOverride ?? _instance;

  @visibleForTesting
  static void overrideForTest(SecurityService service) {
    _testOverride = service;
  }

  @visibleForTesting
  static void resetTestOverride() {
    _testOverride = null;
  }

  static const _dbKeyStorageKey = 'db_encryption_key';
  static const _passwordHashKey = 'lock_password_hash';
  static const _passwordSaltKey = 'lock_password_salt';
  static const _biometricToggleKey = 'lock_biometric_enabled';
  // Opt-in cloud AI (Gemini). New namespace, not the legacy key, so the
  // one-shot legacy purge below can never race with a freshly-set V2 key.
  static const _geminiApiKeyV2Key = 'gemini_api_key_v2';
  // Legacy keys retained only to purge data left over from the removed
  // Gemini integration.
  static const _legacyGeminiApiKeyKey = 'gemini_api_key';
  static const _legacyAiCachePrefsKeys = [
    'ai_recommendations_cache',
    'ai_recommendations_fingerprint',
    'ai_recommendations_timestamp',
  ];
  static const _legacyGeminiPurgedFlagKey = 'legacy_gemini_purged';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Lazily generates and returns the SQLCipher key used to encrypt the database.
  Future<String> obtainDatabaseKey() async {
    // Fire-and-forget: don't block DB init on legacy cleanup.
    unawaited(_purgeLegacyGeminiData());
    try {
      final existing = await _secureStorage.read(key: _dbKeyStorageKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }
    } catch (e) {
      debugPrint('Secure storage read failed, checking fallback: $e');
    }

    try {
      final fallback = await _getFallbackKey();
      if (fallback != null) return fallback;
    } catch (e) {
      debugPrint('Fallback read failed: $e');
    }

    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    final encoded = base64Encode(bytes);

    try {
      await _secureStorage.write(key: _dbKeyStorageKey, value: encoded);
    } catch (e) {
      debugPrint('Secure storage write failed, saving to fallback: $e');
      await _saveFallbackKey(encoded);
    }
    return encoded;
  }

  Future<String?> _getFallbackKey() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, '.db_key'));
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  Future<void> _saveFallbackKey(String key) async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, '.db_key'));
    await file.writeAsString(key);
  }

  Future<void> _purgeLegacyGeminiData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_legacyGeminiPurgedFlagKey) ?? false) return;

      try {
        await _secureStorage.delete(key: _legacyGeminiApiKeyKey);
      } catch (e) {
        debugPrint('Legacy Gemini key purge failed: $e');
        return; // Don't set the flag if secure-storage delete failed.
      }
      await Future.wait(
        _legacyAiCachePrefsKeys.map((key) => prefs.remove(key)),
      );
      await prefs.setBool(_legacyGeminiPurgedFlagKey, true);
    } catch (e) {
      debugPrint('Legacy Gemini data purge failed: $e');
    }
  }

  /// Whether a Gemini API key is stored for the opt-in cloud AI path.
  Future<bool> hasGeminiApiKey() async {
    final key = await _secureStorage.read(key: _geminiApiKeyV2Key);
    return key != null && key.isNotEmpty;
  }

  /// Stores the user-supplied Gemini API key. Pass `null` or empty to
  /// clear it. The key is held in platform secure storage
  /// (Keychain/Keystore) and only ever leaves the device in the
  /// Authorization header of requests to generativelanguage.googleapis.com.
  Future<void> setGeminiApiKey(String? key) async {
    if (key == null || key.isEmpty) {
      await _secureStorage.delete(key: _geminiApiKeyV2Key);
      return;
    }
    await _secureStorage.write(key: _geminiApiKeyV2Key, value: key);
  }

  /// Retrieves the stored Gemini API key, or `null` if none is set.
  Future<String?> getGeminiApiKey() async {
    return _secureStorage.read(key: _geminiApiKeyV2Key);
  }

  /// Indicates whether a passcode has been configured.
  Future<bool> hasPasscode() async {
    final hash = await _secureStorage.read(key: _passwordHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Enables or disables the passcode lock. Passing `null` clears the lock.
  Future<void> setPasscode(String? passcode) async {
    if (passcode == null || passcode.isEmpty) {
      await _secureStorage.delete(key: _passwordHashKey);
      await _secureStorage.delete(key: _passwordSaltKey);
      await _secureStorage.delete(key: _biometricToggleKey);
      return;
    }

    final salt = _generateSalt();
    final hash = _hashPasscode(passcode, salt);
    await _secureStorage.write(
      key: _passwordSaltKey,
      value: base64Encode(salt),
    );
    await _secureStorage.write(key: _passwordHashKey, value: hash);
  }

  /// Validates the supplied passcode against stored credentials.
  Future<bool> verifyPasscode(String passcode) async {
    final storedHash = await _secureStorage.read(key: _passwordHashKey);
    final storedSalt = await _secureStorage.read(key: _passwordSaltKey);
    if (storedHash == null || storedSalt == null) {
      return false;
    }

    final salt = base64Decode(storedSalt);
    final computed = _hashPasscode(passcode, salt);
    return _secureEquals(computed.codeUnits, storedHash.codeUnits);
  }

  /// Whether biometric authentication is currently toggled on.
  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: _biometricToggleKey);
    return value == 'true';
  }

  /// Toggles biometric authentication. Returns `false` when the requested state
  /// cannot be satisfied (e.g., no biometrics available).
  Future<bool> setBiometricEnabled(bool enabled) async {
    final canUse = await canUseBiometrics();
    if (!enabled) {
      await _secureStorage.write(key: _biometricToggleKey, value: 'false');
      return true;
    }

    if (!canUse) {
      return false;
    }

    await _secureStorage.write(key: _biometricToggleKey, value: 'true');
    return true;
  }

  /// Returns true if the device is capable of using biometrics and the user has
  /// at least one biometric enrolled.
  Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      final hasEnrolled = await _localAuth.getAvailableBiometrics();
      return canCheck && supported && hasEnrolled.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// Attempts biometric authentication, returning true on success.
  Future<bool> authenticateWithBiometrics() async {
    try {
      final result = await _localAuth.authenticate(
        localizedReason: 'Unlock your private address book',
      );
      return result;
    } on Exception {
      return false;
    }
  }

  /// Securely deletes the encrypted database, rolling backups, and all stored
  /// credentials. Returns `true` when data was removed.
  Future<bool> secureDeleteAllData() async {
    // 1. Close any open database connection via DBHelper to release file locks.
    await DBHelper().close();

    final databasesPath = await getDatabasesPath();
    final dbFile = File(
      p.join(databasesPath, StorageConstants.databaseFileName),
    );
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      p.join(docsDir.path, StorageConstants.backupDirectory),
    );

    var removedAnything = false;

    // 2. Clear credentials from secure storage first.
    await _secureStorage.delete(key: _dbKeyStorageKey);
    await _secureStorage.delete(key: _passwordHashKey);
    await _secureStorage.delete(key: _passwordSaltKey);
    await _secureStorage.delete(key: _biometricToggleKey);
    await _secureStorage.delete(key: _legacyGeminiApiKeyKey);
    await _secureStorage.delete(key: _geminiApiKeyV2Key);

    // 3. Securely wipe and remove database files.
    if (await dbFile.exists()) {
      await _securelyWipeFile(dbFile);
      removedAnything = true;
    }

    // Also wipe WAL and SHM files if they exist (common for SQLite)
    final walFile = File('${dbFile.path}-wal');
    if (await walFile.exists()) {
      await _securelyWipeFile(walFile);
    }
    final shmFile = File('${dbFile.path}-shm');
    if (await shmFile.exists()) {
      await _securelyWipeFile(shmFile);
    }

    // Also close any other cached databases and handle sqflite cleanup.
    await closeDatabases();

    // 4. Clean up backups.
    if (await backupDir.exists()) {
      final backups = await backupDir.list().toList();
      await Future.wait(backups.whereType<File>().map(_securelyWipeFile));
      await backupDir.delete(recursive: true);
      removedAnything = true;
    }

    // 5. Remove any downloaded AI model files. These don't contain user
    // data but they're large and re-downloading them after a purge is the
    // user's explicit intent.
    final supportDir = await getApplicationSupportDirectory();
    final aiDir = Directory(p.join(supportDir.path, 'ai_models'));
    if (await aiDir.exists()) {
      await aiDir.delete(recursive: true);
      removedAnything = true;
    }
    await _secureStorage.delete(key: 'ai.huggingface_token');

    return removedAnything;
  }

  Future<void> closeDatabases() async {
    final databasesPath = await getDatabasesPath();
    final dbFile = File(
      p.join(databasesPath, StorageConstants.databaseFileName),
    );
    final dbPath = dbFile.path;
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } on DatabaseException {
      // Ignore when the database has already been removed or was never created.
    }
  }

  bool _secureEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  List<int> _generateSalt() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  String _hashPasscode(String passcode, List<int> salt) {
    final passcodeBytes = utf8.encode(passcode);
    final input = <int>[...salt, ...passcodeBytes];
    final hash = sha256.convert(input);
    return base64Encode(hash.bytes);
  }

  Future<void> _securelyWipeFile(File file) async {
    final length = await file.length();
    final raf = await file.open(mode: FileMode.write);
    const chunkSize = 4096;
    final zeros = List<int>.filled(chunkSize, 0);

    var remaining = length;
    while (remaining > 0) {
      final toWrite = remaining > chunkSize ? chunkSize : remaining;
      await raf.writeFrom(zeros, 0, toWrite);
      remaining -= toWrite;
    }

    await raf.close();
    await file.delete();
  }
}
