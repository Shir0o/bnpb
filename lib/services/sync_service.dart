import 'dart:io';

import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import '../db/db_helper.dart';
import 'reminder_coordinator.dart';

enum SyncType { local, googleDrive }

class SyncConfigurationException implements Exception {
  final String message;

  const SyncConfigurationException(this.message);

  @override
  String toString() => message;
}

class SyncConfigurationStatus {
  final SyncType syncType;
  final bool canSync;
  final String label;
  final String detail;
  final String? path;

  const SyncConfigurationStatus({
    required this.syncType,
    required this.canSync,
    required this.label,
    required this.detail,
    this.path,
  });
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _prefKeySyncDir = 'sync_directory_path';
  static const String _prefKeySyncType = 'sync_type';
  static const String _prefKeyDriveCursorPrefix = 'google_drive_sync_cursor_';

  /// Drive's listing can lag and device clocks drift, so incremental listings
  /// re-check this much before the cursor. Processed files are deduped.
  static const Duration _driveCursorOverlap = Duration(seconds: 60);
  static const Duration _liveSyncBaseInterval = Duration(seconds: 10);
  static const Duration _liveSyncMaxInterval = Duration(minutes: 2);

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

  Timer? _liveSyncTimer;
  Duration _liveSyncInterval = _liveSyncBaseInterval;
  // Bumped whenever the loop starts or stops, so in-flight ticks from an
  // earlier run don't reschedule themselves.
  int _liveSyncGeneration = 0;

  Stream<void> get onSyncComplete => _syncCompleteController.stream;

  /// Broadcasts a sync-complete signal to active views (e.g. after database restore).
  void notifySyncComplete() {
    if (!_syncCompleteController.isClosed) {
      _syncCompleteController.add(null);
    }
  }

  /// Live Google Drive sync: forward every app lifecycle change here.
  ///
  /// [AppLifecycleState.resumed] starts the loop and syncs right away (the
  /// returned future completes after that sync); `inactive` keeps it running;
  /// `hidden`, `paused` and `detached` stop it. The loop only runs while the
  /// sync type is Google Drive.
  Future<void> handleLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        _stopLiveSync();
        await _liveSyncTick(_liveSyncGeneration);
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopLiveSync();
    }
  }

  void _stopLiveSync() {
    _liveSyncGeneration++;
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  /// One live sync: a full Drive sync that ignores the cooldown and never
  /// throws. Failures back off the interval; a success resets it.
  Future<void> _liveSyncTick(int generation) async {
    // Not rescheduling ends the loop, e.g. after switching to a local folder.
    if (await getSyncType() != SyncType.googleDrive) return;
    if (generation != _liveSyncGeneration) return;

    // A tick that would overlap a running sync is skipped, not queued.
    if (!_isSyncing) {
      try {
        await _syncNow();
        _liveSyncInterval = _liveSyncBaseInterval;
      } catch (e) {
        final doubled = _liveSyncInterval * 2;
        _liveSyncInterval =
            doubled > _liveSyncMaxInterval ? _liveSyncMaxInterval : doubled;
        if (kDebugMode) {
          print('Live sync failed, next try in $_liveSyncInterval: $e');
        }
      }
    }

    if (generation != _liveSyncGeneration) return;
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer(
      _liveSyncInterval,
      () => _liveSyncTick(generation),
    );
  }

  @visibleForTesting
  void resetForTest() {
    _stopLiveSync();
    _liveSyncInterval = _liveSyncBaseInterval;
    _lastSyncTime = null;
    _isSyncing = false;
  }

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

  Future<SyncConfigurationStatus> getConfigurationStatus() async {
    final syncType = await getSyncType();

    if (syncType == SyncType.local) {
      final path = await getSyncDirectory();
      if (path == null || path.trim().isEmpty) {
        return const SyncConfigurationStatus(
          syncType: SyncType.local,
          canSync: false,
          label: 'Sync folder required',
          detail: 'Choose a folder shared with your mobile device.',
        );
      }

      final directory = Directory(path);
      if (!await directory.exists()) {
        return SyncConfigurationStatus(
          syncType: SyncType.local,
          canSync: false,
          label: 'Sync folder unavailable',
          detail: 'Choose another folder or reconnect the selected location.',
          path: path,
        );
      }

      return SyncConfigurationStatus(
        syncType: SyncType.local,
        canSync: true,
        label: 'Local folder ready',
        detail: 'Changes sync through the selected shared folder.',
        path: path,
      );
    }

    final user = await _googleDrive.currentUser;
    if (user == null) {
      return const SyncConfigurationStatus(
        syncType: SyncType.googleDrive,
        canSync: false,
        label: 'Google Drive sign-in required',
        detail: 'Sign in to Google Drive with the same account used on mobile.',
      );
    }

    return SyncConfigurationStatus(
      syncType: SyncType.googleDrive,
      canSync: true,
      label: 'Google Drive ready',
      detail: 'Signed in as ${user.email}.',
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

    try {
      return await _syncNow(validateConfiguration: rethrowErrors);
    } catch (e) {
      if (rethrowErrors) rethrow;
      return false;
    }
  }

  /// Runs one sync now and lets errors propagate. Callers check [_isSyncing].
  Future<bool> _syncNow({bool validateConfiguration = false}) async {
    _isSyncing = true;
    _lastSyncTime = DateTime.now();
    final syncType = await getSyncType();
    bool hasChanges = false;

    try {
      if (validateConfiguration) {
        await _ensureConfiguredForManualSync();
      }
      if (syncType == SyncType.local) {
        hasChanges = await _performLocalSync();
      } else {
        hasChanges = await _performGoogleSync();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Sync failed: $e');
      }
      rethrow;
    } finally {
      _isSyncing = false;
      if (hasChanges) {
        _syncCompleteController.add(null);
      }
    }
    return hasChanges;
  }

  Future<void> _ensureConfiguredForManualSync() async {
    final status = await getConfigurationStatus();
    if (!status.canSync) {
      throw SyncConfigurationException(status.detail);
    }
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
      // 1. Download files from Google Drive to temp dir. After the first
      // sync, only list files created since the cursor.
      final prefs = await SharedPreferences.getInstance();
      final cursorKey = '$_prefKeyDriveCursorPrefix${user.email}';
      final cursorIso = prefs.getString(cursorKey);
      final remoteFiles = cursorIso == null
          ? await _googleDrive.listSyncFiles()
          : await _googleDrive.listSyncFilesCreatedSince(
              DateTime.parse(cursorIso).subtract(_driveCursorOverlap),
            );
      final processedFiles = await _coordinator.getProcessedFiles();
      final deviceId = await _coordinator.getDeviceId();

      final filesToDownload = remoteFiles.where((file) {
        if (file.name == null || file.id == null) return false;
        final name = file.name!;
        if (!name.endsWith('_data.json')) return false;
        if (name.startsWith(deviceId)) return false;
        return !processedFiles.contains(name);
      }).toList()
        ..sort((a, b) {
          final timestampA = _extractTimestamp(a.name!);
          final timestampB = _extractTimestamp(b.name!);
          return timestampA.compareTo(timestampB);
        });

      // Download in parallel batches
      await _processInBatches<drive.File>(filesToDownload, (file) async {
        if (kDebugMode) {
          print('-> Downloading sync delta: ${file.name}');
        }
        final targetFile = File(p.join(syncTempDir.path, file.name!));
        await _googleDrive.downloadFile(file.id!, targetFile);
      });

      // 2. Run standard SyncCoordinator logic on temp dir
      // This will import the downloaded files and mark them as processed.
      final importResult = await _coordinator.importChanges(syncTempDir);

      // Advance the cursor to the newest listed file, but not past a file
      // that still isn't imported, so it gets listed again next time.
      final processedAfterImport = await _coordinator.getProcessedFiles();
      final notImported = filesToDownload
          .where((f) => !processedAfterImport.contains(f.name))
          .toList();
      final nextCursor = notImported.isNotEmpty
          ? _sortedCreatedTimes(notImported).firstOrNull
          : _sortedCreatedTimes(remoteFiles).lastOrNull;
      if (nextCursor != null) {
        await prefs.setString(cursorKey, nextCursor.toUtc().toIso8601String());
      }

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

  List<DateTime> _sortedCreatedTimes(List<drive.File> files) =>
      files.map((f) => f.createdTime).whereType<DateTime>().toList()..sort();

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
