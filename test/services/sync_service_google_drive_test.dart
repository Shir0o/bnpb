import 'dart:async';
import 'dart:io';

import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/sync_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
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

/// Stands in for the sync temp dir so fake_async can drive whole syncs:
/// real directory I/O only completes on the real event loop.
class InMemoryDirectory extends Fake implements Directory {
  InMemoryDirectory(this.path);

  @override
  final String path;

  @override
  Future<bool> exists() async => true;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      const Stream.empty();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;
}

/// Runs [body] in fake time with the sync temp dir kept in memory.
void runInFakeTime(void Function(FakeAsync async) body) {
  IOOverrides.runZoned(
    () => fakeAsync(body),
    createDirectory: InMemoryDirectory.new,
  );
}

void main() {
  late Directory tempDir;
  late MockGoogleDriveService googleDrive;
  late MockSyncCoordinator coordinator;
  late SyncService syncService;

  setUpAll(() {
    registerFallbackValue(Directory('.'));
    registerFallbackValue(File('.'));
    registerFallbackValue(DateTime.utc(2000));
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
    syncService.resetForTest();
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

      when(() => googleDrive.listSyncFiles())
          .thenAnswer((_) async => remoteFiles);
      final downloadedNames = <String>[];
      when(() => googleDrive.downloadFile(any(), any()))
          .thenAnswer((invocation) {
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

  group('live Google Drive sync', () {
    late int listCount;

    setUp(() {
      listCount = 0;
      when(() => googleDrive.listSyncFiles()).thenAnswer((_) async {
        listCount++;
        return [];
      });
    });

    /// Asserts the next tick happens exactly [interval] from now.
    void expectNextTickAfter(FakeAsync async, Duration interval) {
      final before = listCount;
      async.elapse(interval - const Duration(seconds: 1));
      expect(listCount, before, reason: 'ticked before $interval');
      async.elapse(const Duration(seconds: 1));
      expect(listCount, before + 1, reason: 'no tick after $interval');
    }

    test('resumed syncs right away and then every 10 seconds', () {
      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(listCount, 1);

        expectNextTickAfter(async, const Duration(seconds: 10));
        expectNextTickAfter(async, const Duration(seconds: 10));

        syncService.handleLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
      });
    });

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      test('${state.name} stops the loop', () {
        runInFakeTime((async) {
          syncService.handleLifecycleState(AppLifecycleState.resumed);
          async.flushMicrotasks();
          syncService.handleLifecycleState(state);
          async.elapse(const Duration(minutes: 5));

          expect(listCount, 1);
        });
      });
    }

    test('inactive keeps the loop running', () {
      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        syncService.handleLifecycleState(AppLifecycleState.inactive);
        async.flushMicrotasks();

        expectNextTickAfter(async, const Duration(seconds: 10));

        syncService.handleLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
      });
    });

    test('live ticks bypass the cooldown that performSync still respects', () {
      runInFakeTime((async) {
        syncService.performSync();
        async.flushMicrotasks();
        expect(listCount, 1);

        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(listCount, 2, reason: 'the resume tick ignores the cooldown');
        expectNextTickAfter(async, const Duration(seconds: 10));

        syncService.handleLifecycleState(AppLifecycleState.paused);
        syncService.performSync();
        async.flushMicrotasks();
        expect(listCount, 3, reason: 'automatic syncs keep the cooldown');
      });
    });

    test('never starts with local folder sync', () {
      SharedPreferences.setMockInitialValues({
        'sync_type': 'local',
        'sync_directory_path': tempDir.path,
      });

      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(minutes: 5));
      });

      verifyNever(() => coordinator.importChanges(any()));
      verifyNever(() => coordinator.exportChanges(any()));
    });

    test('stops at the next tick after switching to local folder sync', () {
      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(listCount, 1);

        syncService.setSyncType(SyncType.local);
        async.elapse(const Duration(minutes: 5));

        expect(listCount, 1);
        verify(() => coordinator.importChanges(any())).called(1);
      });
    });

    test('does nothing and never prompts for sign-in while signed out', () {
      when(() => googleDrive.currentUser).thenAnswer((_) async => null);

      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 30));
        syncService.handleLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
      });

      verify(() => googleDrive.currentUser).called(greaterThan(1));
      expect(listCount, 0);
      verifyNever(() => googleDrive.signIn());
      verifyNever(() => googleDrive.requestDrivePermissions());
      verifyNever(() => coordinator.importChanges(any()));
    });

    test('skips a tick that would overlap a running sync', () {
      // Created in fake time below so its completion runs on fake microtasks.
      late Completer<List<drive.File>> slowListing;
      when(() => googleDrive.listSyncFiles()).thenAnswer((_) {
        listCount++;
        return listCount == 1 ? slowListing.future : Future.value([]);
      });

      runInFakeTime((async) {
        slowListing = Completer();
        syncService.performSync(force: true);
        async.flushMicrotasks();
        expect(listCount, 1);

        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 25));
        expect(listCount, 1, reason: 'ticks during a sync are skipped');

        slowListing.complete([]);
        async.flushMicrotasks();
        expect(listCount, 1, reason: 'skipped ticks are not queued');

        async.elapse(const Duration(seconds: 5));
        expect(listCount, 2);

        syncService.handleLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
      });
    });

    test('backs off after consecutive failures and resets after a success', () {
      var failing = true;
      when(() => googleDrive.listSyncFiles()).thenAnswer((_) async {
        listCount++;
        if (failing) throw Exception('offline');
        return [];
      });

      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(listCount, 1);

        for (final seconds in [20, 40, 80, 120, 120]) {
          expectNextTickAfter(async, Duration(seconds: seconds));
        }

        failing = false;
        expectNextTickAfter(async, const Duration(minutes: 2));
        expectNextTickAfter(async, const Duration(seconds: 10));
        expectNextTickAfter(async, const Duration(seconds: 10));

        syncService.handleLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
      });
    });

    test('onSyncComplete fires only when a tick imports something', () {
      var completions = 0;
      final subscription = syncService.onSyncComplete.listen(
        (_) => completions++,
      );

      runInFakeTime((async) {
        syncService.handleLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(completions, 0);

        when(() => coordinator.importChanges(any())).thenAnswer(
          (_) async => const SyncResult(exportedCount: 0, importedCount: 1),
        );
        async.elapse(const Duration(seconds: 10));
        expect(completions, 1);

        syncService.handleLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
      });

      subscription.cancel();
    });
  });

  group('incremental Drive listing', () {
    final firstCreated = DateTime.utc(2026, 10, 15, 12);
    final secondCreated = DateTime.utc(2026, 10, 15, 12, 5);

    drive.File deltaFile(String name, DateTime createdTime) => drive.File()
      ..id = name
      ..name = name
      ..createdTime = createdTime;

    late Set<String> processed;

    setUp(() {
      processed = {};
      when(() => coordinator.getProcessedFiles())
          .thenAnswer((_) async => {...processed});
      when(() => googleDrive.downloadFile(any(), any())).thenAnswer(
        (invocation) =>
            (invocation.positionalArguments[1] as File).writeAsString('{}'),
      );
      when(() => coordinator.importChanges(any())).thenAnswer((_) async {
        final dir = Directory(p.join(tempDir.path, 'google_sync'));
        final names = dir.listSync().map((f) => p.basename(f.path));
        processed.addAll(names);
        return SyncResult(exportedCount: 0, importedCount: names.length);
      });
      when(() => googleDrive.listSyncFilesCreatedSince(any()))
          .thenAnswer((_) async => []);
    });

    test('the first sync uses the full listing', () async {
      when(() => googleDrive.listSyncFiles()).thenAnswer((_) async => []);

      await syncService.performSync(force: true);

      verify(() => googleDrive.listSyncFiles()).called(1);
      verifyNever(() => googleDrive.listSyncFilesCreatedSince(any()));
    });

    test(
      'later syncs list files created since the newest seen, minus 60s',
      () async {
        when(() => googleDrive.listSyncFiles()).thenAnswer(
          (_) async => [
            deltaFile('phone_1000_data.json', firstCreated),
            deltaFile('mac_2000_data.json', secondCreated),
          ],
        );

        await syncService.performSync(force: true);
        await syncService.performSync(force: true);

        verify(() => googleDrive.listSyncFiles()).called(1);
        verify(
          () => googleDrive.listSyncFilesCreatedSince(
            secondCreated.subtract(const Duration(seconds: 60)),
          ),
        ).called(1);
      },
    );

    test('the cursor does not advance when the import fails', () async {
      when(() => googleDrive.listSyncFiles()).thenAnswer(
        (_) async => [deltaFile('phone_1000_data.json', firstCreated)],
      );
      await syncService.performSync(force: true);

      when(() => googleDrive.listSyncFilesCreatedSince(any())).thenAnswer(
        (_) async => [deltaFile('phone_2000_data.json', secondCreated)],
      );
      when(() => coordinator.importChanges(any()))
          .thenThrow(Exception('database locked'));
      await syncService.performSync(force: true);
      await syncService.performSync(force: true);

      verify(
        () => googleDrive.listSyncFilesCreatedSince(
          firstCreated.subtract(const Duration(seconds: 60)),
        ),
      ).called(2);
    });

    test('a delta file that was not imported is listed again', () async {
      when(() => googleDrive.listSyncFiles()).thenAnswer(
        (_) async => [
          deltaFile('phone_1000_data.json', firstCreated),
          deltaFile('phone_2000_data.json', secondCreated),
        ],
      );
      when(() => coordinator.importChanges(any())).thenAnswer((_) async {
        processed.add('phone_2000_data.json');
        return const SyncResult(exportedCount: 0, importedCount: 1);
      });

      await syncService.performSync(force: true);
      await syncService.performSync(force: true);

      verify(
        () => googleDrive.listSyncFilesCreatedSince(
          firstCreated.subtract(const Duration(seconds: 60)),
        ),
      ).called(1);
    });

    test('files already processed are not downloaded again', () async {
      final file = deltaFile('phone_1000_data.json', firstCreated);
      when(() => googleDrive.listSyncFiles()).thenAnswer((_) async => [file]);
      when(() => googleDrive.listSyncFilesCreatedSince(any()))
          .thenAnswer((_) async => [file]);

      await syncService.performSync(force: true);
      await syncService.performSync(force: true);

      verify(() => googleDrive.downloadFile(any(), any())).called(1);
    });
  });
}
