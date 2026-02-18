import 'dart:io';

import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/db_helper.dart';
import 'reminder_coordinator.dart';

enum SyncType { local, googleDrive }

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _prefKeySyncDir = 'sync_directory_path';
  static const String _prefKeySyncType = 'sync_type';

  final SyncCoordinator _coordinator = SyncCoordinator(DBHelper());
  final GoogleDriveService _googleDrive = GoogleDriveService();

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

  Future<SyncType> getSyncType() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(_prefKeySyncType);
    if (typeStr == 'googleDrive') return SyncType.googleDrive;
    return SyncType.local;
  }

  Future<void> setSyncType(SyncType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySyncType,
        type == SyncType.googleDrive ? 'googleDrive' : 'local');
  }

  /// Performs a full sync: Import then Export.
  Future<void> performSync() async {
    final syncType = await getSyncType();

    try {
      if (syncType == SyncType.local) {
        await _performLocalSync();
      } else {
        await _performGoogleSync();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Sync failed: $e');
      }
      // We don't rethrow here to prevent app crashes during background/pause syncs
    }
  }

  Future<void> _performLocalSync() async {
    final syncDirPath = await getSyncDirectory();
    if (syncDirPath == null) return;
    final syncDir = Directory(syncDirPath);

    try {
      // 1. Import remote changes first
      await _coordinator.importChanges(syncDir);

      // 2. Export local changes
      await _coordinator.exportChanges(syncDir);
    } catch (e) {
      if (kDebugMode) {
        print('Local sync failed: $e');
      }
      rethrow;
    }
  }

  Future<void> _performGoogleSync() async {
    if (!await _googleDrive.isSignedIn()) {
      final account = await _googleDrive.signIn();
      if (account == null) throw Exception('Google Sign-In failed');
    }

    final tempDir = await getTemporaryDirectory();
    final syncTempPath = p.join(tempDir.path, 'google_sync');
    final syncTempDir = Directory(syncTempPath);
    if (!await syncTempDir.exists()) {
      await syncTempDir.create(recursive: true);
    }

    try {
      // 1. Download files from Google Drive to temp dir
      final remoteFiles = await _googleDrive.listSyncFiles();
      for (final file in remoteFiles) {
        if (file.id != null && file.name != null) {
          final targetFile = File(p.join(syncTempDir.path, file.name));
          await _googleDrive.downloadFile(file.id!, targetFile);
        }
      }

      // 2. Run standard SyncCoordinator logic on temp dir
      await _coordinator.importChanges(syncTempDir);
      await _coordinator.exportChanges(syncTempDir);

      // 3. Upload new/updated files back to Google Drive
      final localFiles = syncTempDir.listSync().whereType<File>();
      for (final file in localFiles) {
        await _googleDrive.uploadFile(file, p.basename(file.path));
      }

      // 4. Cleanup temp dir
      // We could keep it, but for privacy/security better to wipe.
      // However, SyncCoordinator relies on knowing which files it has processed.
      // Wait: SyncCoordinator stores processed filenames in SharedPreferences.
      // So wiping the physical files is fine.
    } catch (e) {
      if (kDebugMode) {
        print('Google sync failed: $e');
      }
      rethrow;
    } finally {
      if (await syncTempDir.exists()) {
        await syncTempDir.delete(recursive: true);
      }
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
    final syncType = await getSyncType();
    if (syncType == SyncType.local) {
      final syncDirPath = await getSyncDirectory();
      if (syncDirPath == null) return;
      final syncDir = Directory(syncDirPath);
      await _coordinator.importChanges(syncDir);
    } else {
      // For Google Drive, we need to download and merge.
      // We can just call _performGoogleSync() as it handles both directions safely.
      await _performGoogleSync();
    }

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
