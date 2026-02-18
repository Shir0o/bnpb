import 'dart:io';

import 'package:bnpb/services/sync_coordinator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/db_helper.dart';
import 'reminder_coordinator.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _prefKeySyncDir = 'sync_directory_path';

  final SyncCoordinator _coordinator = SyncCoordinator(DBHelper());

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

  /// Performs a full sync: Import then Export.
  Future<void> performSync() async {
    final syncDirPath = await getSyncDirectory();
    if (syncDirPath == null) return;
    final syncDir = Directory(syncDirPath);

    try {
      // 1. Import remote changes first to ensure we base our updates on latest state
      await _coordinator.importChanges(syncDir);

      // 2. Export local changes
      await _coordinator.exportChanges(syncDir);
    } catch (e) {
      if (kDebugMode) {
        print('Sync failed: $e');
      }
      rethrow;
    }
  }

  // Legacy alias for compatibility if UI calls it
  Future<void> performBackup() async {
    // On pause/background, we at least want to export.
    // We could also import to ensure we are up to date, but export is critical for safely saving work.
    // Changing to full sync for robustness.
    await performSync();
  }

  // Legacy alias for restore
  Future<void> restoreFromLatestBackup() async {
    final syncDirPath = await getSyncDirectory();
    if (syncDirPath == null) return;
    final syncDir = Directory(syncDirPath);
    await _coordinator.importChanges(syncDir);

    // Refresh UI?
    // The original code called ReminderCoordinator().refreshAllContacts();
    await ReminderCoordinator().refreshAllContacts();
  }

  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    // Reusing the key from SyncCoordinator if possible, or we can just look at file stats?
    // SyncCoordinator uses 'sync_last_export_time'.
    final iso = prefs.getString('sync_last_export_time');
    if (iso != null) {
      return DateTime.parse(iso);
    }
    return null;
  }

  Future<bool> checkForUpdates() async {
    // Check if there are unprocessed files in sync dir.
    // For now, return false to avoid triggering the "Overwrite" dialog in main.dart.
    // Differential sync should probably happen silently or via explicit Sync.
    return false;
  }
}
