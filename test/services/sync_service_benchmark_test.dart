import 'dart:io';

import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async {
    return tempDir.path;
  }
}

void main() {
  late SyncService syncService;
  late MockGoogleDriveService mockDrive;
  late MockSyncCoordinator mockCoordinator;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(Directory('.'));
    registerFallbackValue(drive.File());
    registerFallbackValue(File('.')); // For uploadFile(File file, String name)
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    SharedPreferences.setMockInitialValues({'sync_type': 'googleDrive'});

    mockDrive = MockGoogleDriveService();
    mockCoordinator = MockSyncCoordinator();

    syncService = SyncService();
    syncService.googleDriveService = mockDrive;
    syncService.syncCoordinator = mockCoordinator;

    when(() => mockDrive.isSignedIn()).thenAnswer((_) async => true);
    when(() => mockCoordinator.getProcessedFiles()).thenAnswer((_) async => {});
    when(() => mockCoordinator.getDeviceId())
        .thenAnswer((_) async => 'test_device');
    when(() => mockCoordinator.importChanges(any())).thenAnswer(
        (_) async => const SyncResult(exportedCount: 0, importedCount: 0));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('Sync Benchmark: Measures execution time of sync operations', () async {
    // 1. Setup simulated remote files (10 files)
    final remoteFiles = List.generate(
        10,
        (i) => drive.File()
          ..id = 'id_$i'
          ..name = 'file_$i.json');
    when(() => mockDrive.listSyncFiles()).thenAnswer((_) async => remoteFiles);

    // Simulate 50ms delay per download
    when(() => mockDrive.downloadFile(any(), any()))
        .thenAnswer((invocation) async {
      await Future.delayed(const Duration(milliseconds: 50));
    });

    // Simulate export creating 10 new local files
    when(() => mockCoordinator.exportChanges(any()))
        .thenAnswer((invocation) async {
      final dir = invocation.positionalArguments[0] as Directory;
      for (var i = 0; i < 10; i++) {
        File(p.join(dir.path, 'new_export_$i.json')).createSync();
      }
      return const SyncResult(exportedCount: 10, importedCount: 0);
    });

    // Simulate 50ms delay per upload
    when(() => mockDrive.uploadFile(any(), any()))
        .thenAnswer((invocation) async {
      await Future.delayed(const Duration(milliseconds: 50));
    });

    final stopwatch = Stopwatch()..start();
    await syncService.performSync();
    stopwatch.stop();

    print('Sync execution time: ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsedMilliseconds, lessThan(600),
        reason: 'Sync should be parallelized');

    // Expectation: Sequential ~1000ms+ (overhead).
    // We don't assert here, just print.
    // Or we can assert it is SLOWER than optimized (later).
  });
}
