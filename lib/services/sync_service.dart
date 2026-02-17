import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../constants/storage.dart';
import '../db/db_helper.dart';
import 'reminder_coordinator.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _prefKeySyncDir = 'sync_directory_path';
  static const int _maxRetainedBackups = 5;

  Future<void> setSyncDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Sync Folder',
      lockParentWindow: true,
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeySyncDir, result);
    }
  }

  Future<String?> getSyncDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeySyncDir);
  }

  Future<void> performBackup() async {
    final syncDir = await getSyncDirectory();
    if (syncDir == null) return;

    final dbPath = await getDatabasesPath();
    final sourceFile = File(p.join(dbPath, StorageConstants.databaseFileName));

    if (!sourceFile.existsSync()) return;

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final backupPath = p.join(syncDir, 'backup_$timestamp.db');

    try {
      await sourceFile.copy(backupPath);
      await _pruneOldBackups(syncDir);
    } catch (e) {
      if (kDebugMode) {
        print('Backup failed: $e');
      }
    }
  }

  Future<void> _pruneOldBackups(String syncDir) async {
    final dir = Directory(syncDir);
    if (!await dir.exists()) return;

    final entities = await dir.list().toList();
    final files = entities
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('backup_') && f.path.endsWith('.db'))
        .toList();

    files.sort((a, b) => b.path.compareTo(a.path)); // Newest first

    if (files.length > _maxRetainedBackups) {
      for (var i = _maxRetainedBackups; i < files.length; i++) {
        try {
          await files[i].delete();
        } catch (e) {
          // Ignore
        }
      }
    }
  }

  Future<bool> checkForUpdates() async {
    final syncDir = await getSyncDirectory();
    if (syncDir == null) return false;

    final dir = Directory(syncDir);
    if (!await dir.exists()) return false;

    final entities = await dir.list().toList();
    final backups = entities
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('backup_') && f.path.endsWith('.db'))
        .toList();

    if (backups.isEmpty) return false;

    backups.sort((a, b) => b.path.compareTo(a.path)); // Newest first
    final latestBackup = backups.first;

    final dbPath = await getDatabasesPath();
    final localFile = File(p.join(dbPath, StorageConstants.databaseFileName));

    if (!localFile.existsSync()) return true;

    final localStat = await localFile.stat();
    final backupStat = await latestBackup.stat();

    // Check if backup is significantly newer (> 2 seconds to avoid race condition with own backup)
    return backupStat.modified
        .isAfter(localStat.modified.add(const Duration(seconds: 2)));
  }

  Future<void> restoreFromLatestBackup() async {
    final syncDir = await getSyncDirectory();
    if (syncDir == null) return;

    final dir = Directory(syncDir);
    final entities = await dir.list().toList();
    final backups = entities
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('backup_') && f.path.endsWith('.db'))
        .toList();

    if (backups.isEmpty) return;

    backups.sort((a, b) => b.path.compareTo(a.path));
    final latestBackup = backups.first;

    await DBHelper().close();

    final dbPath = await getDatabasesPath();
    final localPath = p.join(dbPath, StorageConstants.databaseFileName);

    await latestBackup.copy(localPath);

    // Re-initialize DB
    await DBHelper().database;
    await ReminderCoordinator().refreshAllContacts();
  }

  Future<DateTime?> getLastBackupTime() async {
    final syncDir = await getSyncDirectory();
    if (syncDir == null) return null;

    final dir = Directory(syncDir);
    if (!await dir.exists()) return null;

    final entities = await dir.list().toList();
    final backups = entities
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('backup_') && f.path.endsWith('.db'))
        .toList();

    if (backups.isEmpty) return null;

    backups.sort((a, b) => b.path.compareTo(a.path));
    try {
      return (await backups.first.stat()).modified;
    } catch (e) {
      return null;
    }
  }
}
