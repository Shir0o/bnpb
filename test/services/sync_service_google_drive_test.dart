import 'dart:io';

import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;

  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  late Directory tempDir;
  late MockGoogleDriveService googleDrive;
  late MockSyncCoordinator coordinator;
  late SyncService syncService;

  setUpAll(() {
    registerFallbackValue(Directory('.'));
    registerFallbackValue(File('.'));
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('google_sync_test');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    SharedPreferences.setMockInitialValues({'sync_type': 'googleDrive'});

    googleDrive = MockGoogleDriveService();
    coordinator = MockSyncCoordinator();
    syncService = SyncService()
      ..googleDriveService = googleDrive
      ..syncCoordinator = coordinator;

    final googleUser = MockGoogleSignInAccount();
    when(() => googleUser.email).thenReturn('desktop@example.com');
    when(() => googleDrive.currentUser).thenAnswer((_) async => googleUser);
    when(() => googleDrive.uploadFile(any(), any())).thenAnswer((_) async {});
    when(() => coordinator.getDeviceId()).thenAnswer((_) async => 'mac');
    when(() => coordinator.getProcessedFiles()).thenAnswer((_) async => {});
    when(() => coordinator.importChanges(any())).thenAnswer(
      (_) async => const SyncResult(exportedCount: 0, importedCount: 0),
    );
    when(() => coordinator.exportChanges(any())).thenAnswer(
      (_) async => const SyncResult(exportedCount: 0, importedCount: 0),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'downloads every unprocessed remote delta file from mobile devices',
    () async {
      final remoteFiles = [
        drive.File()
          ..id = 'phone-1000'
          ..name = 'phone_1000_data.json',
        drive.File()
          ..id = 'phone-2000'
          ..name = 'phone_2000_data.json',
        drive.File()
          ..id = 'mac-3000'
          ..name = 'mac_3000_data.json',
      ];

      when(
        () => googleDrive.listSyncFiles(),
      ).thenAnswer((_) async => remoteFiles);
      final downloadedNames = <String>[];
      when(() => googleDrive.downloadFile(any(), any())).thenAnswer((
        invocation,
      ) {
        final targetFile = invocation.positionalArguments[1] as File;
        downloadedNames.add(p.basename(targetFile.path));
        return targetFile.writeAsString('{}');
      });

      await syncService.performSync(force: true, rethrowErrors: true);

      expect(
        downloadedNames,
        ['phone_1000_data.json', 'phone_2000_data.json'],
        reason: 'sync exports are deltas, so skipping older mobile files loses '
            'changes before the latest export',
      );
    },
  );

  test(
    'manual Google Drive sync reports a setup error when signed out',
    () async {
      when(() => googleDrive.currentUser).thenAnswer((_) async => null);

      expect(
        () => syncService.performSync(force: true, rethrowErrors: true),
        throwsA(
          isA<SyncConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('Sign in to Google Drive'),
          ),
        ),
      );
    },
  );

  test(
    'local sync status reports a missing folder before manual sync',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync_type': 'local',
        'sync_directory_path': p.join(tempDir.path, 'missing'),
      });

      final status = await syncService.getConfigurationStatus();

      expect(status.canSync, isFalse);
      expect(status.label, 'Sync folder unavailable');
      expect(
        () => syncService.performSync(force: true, rethrowErrors: true),
        throwsA(isA<SyncConfigurationException>()),
      );
    },
  );
}
