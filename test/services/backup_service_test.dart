import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:bnpb/services/backup_service.dart';
import 'package:bnpb/constants/storage.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  final String documentPath;
  MockPathProviderPlatform(this.documentPath);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentPath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    // Create a temporary directory for the test
    tempDir = await Directory.systemTemp.createTemp('backup_test');
    dbPath = p.join(tempDir.path, 'databases');
    await Directory(dbPath).create();

    // Mock path_provider to return the temp dir
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
    
    // Configure BackupService to use our test db path
    BackupService().mockDatabasePath = dbPath;
  });

  tearDown(() async {
    BackupService().mockDatabasePath = null; // Reset
    // Cleanup
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ensureBackupDirectoryExists creates the backup directory', () async {
    final service = BackupService();
    final dir = await service.ensureBackupDirectoryExists();

    expect(await dir.exists(), isTrue);
    expect(dir.path, endsWith(StorageConstants.backupDirectory));
    expect(p.isWithin(tempDir.path, dir.path), isTrue);
  });

  test('exportBackup returns null if database does not exist', () async {
    final service = BackupService();
    // Ensure no DB file exists
    final dbFile = File(p.join(dbPath, StorageConstants.databaseFileName));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    
    final result = await service.exportBackup();
    expect(result, isNull);
  });

  test('exportBackup creates a backup file when database exists', () async {
    // Create a dummy database file
    final fullPath = p.join(dbPath, StorageConstants.databaseFileName);
    final dbFile = File(fullPath);
    const dbContent = 'dummy database content';
    await dbFile.writeAsString(dbContent);

    final service = BackupService();
    final backup = await service.exportBackup();

    expect(backup, isNotNull);
    expect(await backup!.exists(), isTrue);
    expect(await backup.readAsString(), dbContent);
    expect(p.basename(backup.path), startsWith('backup_'));
    expect(backup.path, endsWith('.db'));

    // Verify it is in the backup directory
    final backupDir = Directory(p.join(tempDir.path, StorageConstants.backupDirectory));
    expect(p.isWithin(backupDir.path, backup.path), isTrue);
  });

  test('listBackups returns existing backups', () async {
    final service = BackupService();
    final backupDir = await service.ensureBackupDirectoryExists();

    final file1 = File(p.join(backupDir.path, 'backup_1.db'));
    final file2 = File(p.join(backupDir.path, 'backup_2.db'));
    
    await file1.create();
    await file2.create();

    // Create a non-backup file to ensure filtering works
    await File(p.join(backupDir.path, 'other.txt')).create();

    final backups = await service.listBackups();
    expect(backups.length, 2);
    expect(backups.any((b) => b.path == file1.path), isTrue);
    expect(backups.any((b) => b.path == file2.path), isTrue);
  });
}
