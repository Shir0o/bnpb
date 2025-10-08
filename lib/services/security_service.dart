import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../constants/storage.dart';

/// Coordinates secure storage, biometric authentication, and data purging.
class SecurityService {
  SecurityService._();

  static final SecurityService _instance = SecurityService._();

  /// Singleton accessor.
  factory SecurityService() => _instance;

  static const _dbKeyStorageKey = 'db_encryption_key';
  static const _passwordHashKey = 'lock_password_hash';
  static const _passwordSaltKey = 'lock_password_salt';
  static const _biometricToggleKey = 'lock_biometric_enabled';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Lazily generates and returns the SQLCipher key used to encrypt the database.
  Future<String> obtainDatabaseKey() async {
    final existing = await _secureStorage.read(key: _dbKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    final encoded = base64Encode(bytes);
    await _secureStorage.write(key: _dbKeyStorageKey, value: encoded);
    return encoded;
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
    await _secureStorage.write(key: _passwordSaltKey, value: base64Encode(salt));
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
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      return result;
    } on Exception {
      return false;
    }
  }

  /// Securely deletes the encrypted database, rolling backups, and all stored
  /// credentials. Returns `true` when data was removed.
  Future<bool> secureDeleteAllData() async {
    final databasesPath = await getDatabasesPath();
    final dbFile = File(p.join(databasesPath, StorageConstants.databaseFileName));
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docsDir.path, StorageConstants.backupDirectory));

    var removedAnything = false;

    if (await dbFile.exists()) {
      await _securelyWipeFile(dbFile);
      removedAnything = true;
    }

    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
      removedAnything = true;
    }

    await _secureStorage.delete(key: _dbKeyStorageKey);
    await _secureStorage.delete(key: _passwordHashKey);
    await _secureStorage.delete(key: _passwordSaltKey);
    await _secureStorage.delete(key: _biometricToggleKey);

    // Close any cached database instance so a fresh key is requested next time.
    await closeDatabases();

    return removedAnything;
  }

  Future<void> closeDatabases() async {
    final databasesPath = await getDatabasesPath();
    final dbFile = File(p.join(databasesPath, StorageConstants.databaseFileName));
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
