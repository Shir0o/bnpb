import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../constants/storage.dart';
import '../db/db_helper.dart';
import '../widgets/crisp_toast.dart';
import 'reminder_coordinator.dart';

/// Represents a single database backup stored on disk.
class BackupSnapshot {
  BackupSnapshot({
    required this.path,
    required this.modified,
    required this.bytes,
  });

  /// Absolute path to the backup file on disk.
  final String path;

  /// Timestamp of the last modification to the snapshot.
  final DateTime modified;

  /// Size of the backup file in bytes.
  final int bytes;

  /// Convenience accessor for the file name component.
  String get fileName => p.basename(path);

  /// Returns the backing [File] instance for the snapshot.
  File get file => File(path);
}

/// Exception raised when a backup operation fails.
class BackupException implements Exception {
  BackupException(this.message, [this.cause]);

  /// Human-readable error message suitable for surfaced UI.
  final String message;

  /// Underlying cause of the exception, when available.
  final Object? cause;

  @override
  String toString() => message;
}

/// Specific exception thrown when restoring a backup fails.
class BackupRestoreException extends BackupException {
  BackupRestoreException(super.message, [super.cause]);
}

/// Provides helper utilities for exporting, enumerating, and restoring backups.
class BackupService {
  BackupService._();

  static final BackupService _instance = BackupService._();
  static BackupService? _testOverride;

  /// Singleton accessor.
  factory BackupService() => _testOverride ?? _instance;

  @visibleForTesting
  static void overrideForTest(BackupService? service) {
    _testOverride = service;
  }

  @visibleForTesting
  String? mockDatabasePath;

  static const _maxRetainedBackups = 5;

  /// Ensures the backup directory exists and returns it.
  Future<Directory> ensureBackupDirectoryExists() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      p.join(documentsDir.path, StorageConstants.backupDirectory),
    );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Creates a copy of the encrypted database in the backup directory and
  /// prunes older snapshots beyond the retention threshold.
  Future<File?> exportBackup() async {
    final backupDir = await ensureBackupDirectoryExists();
    final dbPath = mockDatabasePath ?? await getDatabasesPath();
    final dbFile = File(p.join(dbPath, StorageConstants.databaseFileName));

    if (!await dbFile.exists()) {
      return null;
    }

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final backupPath = p.join(backupDir.path, 'backup_$timestamp.db');
    final createdBackup = await dbFile.copy(backupPath);

    final snapshots = await listBackups();
    final stale = snapshots.skip(_maxRetainedBackups);
    await Future.wait(
      stale.map((snapshot) async {
        final file = File(snapshot.path);
        if (await file.exists()) {
          await file.delete();
        }
      }),
    );

    return createdBackup;
  }

  /// Lists all known backups sorted by modification time, newest first.
  Future<List<BackupSnapshot>> listBackups() async {
    final backupDir = await ensureBackupDirectoryExists();
    final entries = await backupDir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where(
          (file) =>
              file.path.endsWith('.db') &&
              p.basename(file.path).startsWith('backup_'),
        )
        .toList();

    final snapshots = await Future.wait(
      entries.map((file) async {
        final stat = await file.stat();
        return BackupSnapshot(
          path: file.path,
          modified: stat.modified,
          bytes: stat.size,
        );
      }),
    );

    snapshots.sort((a, b) => b.modified.compareTo(a.modified));
    return snapshots;
  }

  /// Restores the selected [snapshot] over the live database.
  ///
  /// When [overlay] is provided, any failure will surface a toast before
  /// rethrowing the error to the caller.
  Future<void> restoreBackup(
    BackupSnapshot snapshot, {
    OverlayState? overlay,
  }) async {
    final backupFile = snapshot.file;
    if (!await backupFile.exists()) {
      const message = 'Backup file could not be found.';
      if (overlay != null) CrispToast.showOnOverlay(overlay, message);
      throw BackupRestoreException(message);
    }

    final dbPath = await getDatabasesPath();
    final liveDbPath = p.join(dbPath, StorageConstants.databaseFileName);
    final liveDbFile = File(liveDbPath);
    final tempPath = '$liveDbPath.original';
    File? originalCopy;

    try {
      if (await liveDbFile.exists()) {
        originalCopy = await liveDbFile.copy(tempPath);
      }

      await DBHelper().close();
      await backupFile.copy(liveDbPath);
      await DBHelper().database;
      await ReminderCoordinator().refreshAllContacts();
    } catch (error) {
      if (originalCopy != null && await originalCopy.exists()) {
        if (await liveDbFile.exists()) {
          await liveDbFile.delete();
        }
        await originalCopy.copy(liveDbPath);
      }

      await DBHelper().close();

      final message = 'Failed to restore backup: ${error.toString()}';
      if (overlay != null) CrispToast.showOnOverlay(overlay, message);
      throw BackupRestoreException(message, error);
    } finally {
      if (originalCopy != null && await originalCopy.exists()) {
        await originalCopy.delete();
      }
    }
  }
}
