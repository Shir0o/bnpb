import 'dart:io';

import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import '../db/db_helper.dart';
import 'reminder_coordinator.dart';

enum SyncType { local, googleDrive }

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _prefKeySyncDir = 'sync_directory_path';
  static const String _prefKeySyncType = 'sync_type';

  SyncCoordinator _coordinator = SyncCoordinator(DBHelper());

  @visibleForTesting
  set syncCoordinator(SyncCoordinator coordinator) =>
      _coordinator = coordinator;
  GoogleDriveService _googleDrive = GoogleDriveService();

  @visibleForTesting
  set googleDriveService(GoogleDriveService service) => _googleDrive = service;

  final StreamController<void> _syncCompleteController =
      StreamController<void>.broadcast();

  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  Stream<void> get onSyncComplete => _syncCompleteController.stream;

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
    await prefs.setString(
      _prefKeySyncType,
      type == SyncType.googleDrive ? 'googleDrive' : 'local',
    );
  }

  /// Performs a full sync: Import then Export.
  /// [force] will skip the cooldown check.
  /// [rethrowErrors] will allow exceptions to propagate (useful for manual UI sync).
  /// Returns true if any changes were imported.
  Future<bool> performSync({
    bool force = false,
    bool rethrowErrors = false,
  }) async {
    if (_isSyncing) return false;

    // Cooldown logic: avoid syncing more than once every 5 minutes automatically.
    // This prevents the "flash" effect on every app resume.
    final now = DateTime.now();
    if (!force &&
        _lastSyncTime != null &&
        now.difference(_lastSyncTime!).inMinutes < 5) {
      if (kDebugMode) {
        print('Sync skipped: cooldown active.');
      }
      return false;
    }

    _isSyncing = true;
    _lastSyncTime = now;
    final syncType = await getSyncType();
    bool hasChanges = false;

    try {
      if (syncType == SyncType.local) {
        hasChanges = await _performLocalSync();
      } else {
        hasChanges = await _performGoogleSync();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Sync failed: $e');
      }
      if (rethrowErrors) rethrow;
    } finally {
      _isSyncing = false;
      if (hasChanges) {
        _syncCompleteController.add(null);
      }
    }
    return hasChanges;
  }

  Future<bool> _performLocalSync() async {
    final syncDirPath = await getSyncDirectory();
    if (syncDirPath == null) return false;
    final syncDir = Directory(syncDirPath);

    try {
      // 1. Import remote changes first
      final importResult = await _coordinator.importChanges(syncDir);

      // 2. Export local changes
      await _coordinator.exportChanges(syncDir);

      return importResult.importedCount > 0;
    } catch (e) {
      if (kDebugMode) {
        print('Local sync failed: $e');
      }
      rethrow;
    }
  }

  Future<bool> _performGoogleSync() async {
    final user = await _googleDrive.currentUser;
    if (user == null) {
      if (kDebugMode) {
        print('Google Sync: Skipping because user is not signed in.');
      }
      return false;
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
      final processedFiles = await _coordinator.getProcessedFiles();
      final deviceId = await _coordinator.getDeviceId();

      // Optimization: Group remote files by deviceId and only take the latest one per device.
      // This drastically reduces the number of files we check and download.
      final latestFilesPerDevice = <String, drive.File>{};
      for (final file in remoteFiles) {
        if (file.name == null || file.id == null) continue;
        final name = file.name!;
        if (!name.endsWith('_data.json')) continue;

        // Skip our own files
        if (name.startsWith(deviceId)) continue;

        // Skip already processed files
        if (processedFiles.contains(name)) continue;

        final fileDeviceId = name.split('_').first;
        final timestamp = _extractTimestamp(name);

        final existing = latestFilesPerDevice[fileDeviceId];
        if (existing == null || timestamp > _extractTimestamp(existing.name!)) {
          latestFilesPerDevice[fileDeviceId] = file;
        }
      }

      final filesToDownload = latestFilesPerDevice.values.toList();

      // Download in parallel batches
      await _processInBatches<drive.File>(filesToDownload, (file) async {
        if (kDebugMode) {
          print('-> Downloading latest from device: ${file.name}');
        }
        final targetFile = File(p.join(syncTempDir.path, file.name!));
        await _googleDrive.downloadFile(file.id!, targetFile);
      });

      // 2. Run standard SyncCoordinator logic on temp dir
      // This will import the downloaded files and mark them as processed.
      final importResult = await _coordinator.importChanges(syncTempDir);

      // Export new local changes
      await _coordinator.exportChanges(syncTempDir);

      // 3. Upload new/updated files back to Google Drive
      final localFiles = await syncTempDir
          .list()
          .where((f) => f is File)
          .cast<File>()
          .toList();
      final remoteFileNames = remoteFiles.map((f) => f.name).toSet();

      final filesToUpload = localFiles.where((file) {
        final name = p.basename(file.path);
        // Upload if it's not in remote files (meaning it's a new export)
        return !remoteFileNames.contains(name);
      }).toList();

      await _processInBatches<File>(filesToUpload, (file) async {
        final name = p.basename(file.path);
        await _googleDrive.uploadFile(file, name);
      });

      return importResult.importedCount > 0;
      // 4. Cleanup temp dir (handled in finally)
    } catch (e) {
      if (kDebugMode) {
        print('Google sync failed: $e');
      }
      rethrow;
    } finally {
      try {
        if (await syncTempDir.exists()) {
          await syncTempDir.delete(recursive: true);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Cleanup failed: $e');
        }
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
      await _performGoogleSync();
    }

    await ReminderCoordinator().refreshAllContacts();
    _syncCompleteController.add(null);
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

  Future<void> _processInBatches<T>(
    List<T> items,
    Future<void> Function(T) process, {
    int batchSize = 5,
  }) async {
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final batch = items.sublist(i, end);
      await Future.wait(batch.map(process));
    }
  }

  int _extractTimestamp(String filename) {
    // Expected: deviceId_timestamp_data.json
    try {
      final withoutSuffix = filename.replaceAll('_data.json', '');
      final lastUnderscore = withoutSuffix.lastIndexOf('_');
      if (lastUnderscore != -1) {
        final tsPart = withoutSuffix.substring(lastUnderscore + 1);
        return int.tryParse(tsPart) ?? 0;
      }
    } catch (_) {}
    return 0;
  }
}
