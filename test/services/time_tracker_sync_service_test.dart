import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/time_tracker_sync_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeTrackerSyncService', () {
    late MockGoogleDriveService mockDriveService;
    late TimeTrackerSyncService syncService;

    const sampleCsv = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Lunch",2025-09-17 11:46:37,2025-09-17 12:46:37,"w/ Abel","Essentials","Contact",1:0:0,60
"Dinner",2025-09-19 22:16:46,2025-09-19 23:03:36,"Boba w/ Benji","Essentials","Contact",0:46:50,46
''';

    final contacts = [
      Contact(id: 'c1', firstName: 'Abel', lastName: 'Smith'),
      Contact(id: 'c2', firstName: 'Benji', lastName: 'Lee'),
    ];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockDriveService = MockGoogleDriveService();
      syncService = TimeTrackerSyncService(driveService: mockDriveService);
    });

    test(
      'getDriveFolderName defaults to Time track and can be configured',
      () async {
        expect(await syncService.getDriveFolderName(), 'Time track');
        await syncService.setDriveFolderName('My Work/Time Logs');
        expect(await syncService.getDriveFolderName(), 'My Work/Time Logs');
      },
    );

    test('name markers default to w/ and with and can be configured', () async {
      expect(await syncService.getNameMarkers(), ['w/', 'with ']);
      await syncService.setNameMarkers('@, ##');
      expect(await syncService.getNameMarkers(), ['@', '##']);
    });

    test(
      'syncFromDrive queries configured folder instead of hardcoded Time track',
      () async {
        await syncService.setDriveFolderName('Custom STT Folder');

        final driveFile = drive.File()
          ..id = 'file_456'
          ..name = 'stt_records_automatic.csv'
          ..modifiedTime = DateTime.parse('2025-09-20 00:00:00Z');

        when(
          () => mockDriveService.findLatestFileInFolder(
            folderName: 'Custom STT Folder',
            namePrefix: 'stt_records_automatic',
          ),
        ).thenAnswer((_) async => driveFile);

        when(() => mockDriveService.downloadFileAsString('file_456'))
            .thenAnswer((_) async => sampleCsv);

        final candidates = await syncService.syncFromDrive(contacts: contacts);

        expect(candidates.length, 2);
        verify(
          () => mockDriveService.findLatestFileInFolder(
            folderName: 'Custom STT Folder',
            namePrefix: 'stt_records_automatic',
          ),
        ).called(1);
      },
    );

    test(
      'syncFromDrive parses candidates from newest file in Time track folder',
      () async {
        final driveFile = drive.File()
          ..id = 'file_123'
          ..name = 'stt_records_automatic (4).csv'
          ..modifiedTime = DateTime.parse('2025-09-20 00:00:00Z');

        when(
          () => mockDriveService.findLatestFileInFolder(
            folderName: 'Time track',
            namePrefix: 'stt_records_automatic',
          ),
        ).thenAnswer((_) async => driveFile);

        when(() => mockDriveService.downloadFileAsString('file_123'))
            .thenAnswer((_) async => sampleCsv);

        final candidates = await syncService.syncFromDrive(contacts: contacts);

        expect(candidates.length, 2);
        expect(candidates[0].activityName, 'Lunch');
        expect(candidates[1].activityName, 'Dinner');
        expect(syncService.stagingQueue.length, 2);
      },
    );

    test(
        'deduplication ignores fingerprints that were already confirmed and imported',
        () async {
      final driveFile = drive.File()
        ..id = 'file_123'
        ..name = 'stt_records_automatic (4).csv';

      when(
        () => mockDriveService.findLatestFileInFolder(
          folderName: 'Time track',
          namePrefix: 'stt_records_automatic',
        ),
      ).thenAnswer((_) async => driveFile);

      when(() => mockDriveService.downloadFileAsString('file_123'))
          .thenAnswer((_) async => sampleCsv);

      // First sync
      final candidates1 = await syncService.syncFromDrive(contacts: contacts);
      expect(candidates1.length, 2);

      // Mark the first candidate as imported
      await syncService.markImported([candidates1.first.fingerprint]);

      // Second sync should only have the 2nd unimported candidate
      final candidates2 = await syncService.syncFromDrive(contacts: contacts);
      expect(candidates2.length, 1);
      expect(candidates2.first.activityName, 'Dinner');
    });

    test(
      'stagingQueue maintains candidates and allows updating or removing',
      () {
        final candidate = CandidateInteraction(
          fingerprint: 'fp1',
          occurredAt: DateTime.now(),
          durationMinutes: 30,
          activityName: 'Coffee',
          summary: 'Coffee w/ Abel',
          matchedContactIds: ['c1'],
          rawComment: 'w/ Abel',
        );

        syncService.setStagingQueue([candidate]);
        expect(syncService.stagingQueue.length, 1);

        // Update candidate
        candidate.summary = 'Morning Coffee w/ Abel';
        syncService.updateCandidate(candidate);
        expect(
          syncService.stagingQueue.first.summary,
          'Morning Coffee w/ Abel',
        );

        // Dismiss / remove candidate
        syncService.removeCandidates([candidate.fingerprint]);
        expect(syncService.stagingQueue, isEmpty);
      },
    );

    test(
        'dismissCandidates persists fingerprints and filters them from future syncs',
        () async {
      final driveFile = drive.File()
        ..id = 'file_123'
        ..name = 'stt_records_automatic (4).csv';

      when(
        () => mockDriveService.findLatestFileInFolder(
          folderName: 'Time track',
          namePrefix: 'stt_records_automatic',
        ),
      ).thenAnswer((_) async => driveFile);

      when(() => mockDriveService.downloadFileAsString('file_123'))
          .thenAnswer((_) async => sampleCsv);

      // First sync
      final candidates1 = await syncService.syncFromDrive(contacts: contacts);
      expect(candidates1.length, 2);
      final dismissedFingerprint = candidates1.first.fingerprint;

      // Dismiss the first candidate
      await syncService.dismissCandidates([dismissedFingerprint]);
      expect(syncService.stagingQueue.length, 1);
      expect(
        await syncService.getDismissedFingerprints(),
        contains(dismissedFingerprint),
      );

      // Second sync should skip the dismissed candidate
      final candidates2 = await syncService.syncFromDrive(contacts: contacts);
      expect(candidates2.length, 1);
      expect(candidates2.first.activityName, 'Dinner');
    });

    test(
      'clearDismissed allows dismissed candidates to be suggested again',
      () async {
        final driveFile = drive.File()
          ..id = 'file_123'
          ..name = 'stt_records_automatic (4).csv';

        when(
          () => mockDriveService.findLatestFileInFolder(
            folderName: 'Time track',
            namePrefix: 'stt_records_automatic',
          ),
        ).thenAnswer((_) async => driveFile);

        when(() => mockDriveService.downloadFileAsString('file_123'))
            .thenAnswer((_) async => sampleCsv);

        final candidates1 = await syncService.syncFromDrive(contacts: contacts);
        await syncService.dismissCandidates([candidates1.first.fingerprint]);
        expect(await syncService.getDismissedFingerprints(), isNotEmpty);

        await syncService.clearDismissed();
        expect(await syncService.getDismissedFingerprints(), isEmpty);

        final candidates2 = await syncService.syncFromDrive(contacts: contacts);
        expect(candidates2.length, 2);
      },
    );
    group('backfillImportedTitles', () {
      final crew = [
        Contact(id: 'c_noe', firstName: 'Noe'),
        Contact(id: 'c_sammy', firstName: 'Sammy', lastName: 'Ortiz'),
        Contact(id: 'c_fernando', firstName: 'Fernando', lastName: 'Perez'),
      ];

      Interaction legacy() => Interaction(
            id: 1,
            occurredAt: DateTime(2025, 9, 21),
            summary: 'Hangout - sammy fernando',
            medium: 'In Person',
            notes: 'noe sammy fernando',
            participantIds: const ['c_noe', 'c_other'],
          );

      test('fixes legacy titles once and adds missing participants', () async {
        final saved = <Interaction>[];
        Future<int> run() => syncService.backfillImportedTitles(
              contacts: crew,
              loadInteractions: () async => [
                legacy(),
                Interaction(
                  id: 2,
                  occurredAt: DateTime(2025, 9, 22),
                  summary: 'Game night',
                  medium: 'In Person',
                  notes: 'noe sammy fernando',
                ),
              ],
              saveInteraction: (i) async => saved.add(i),
            );

        expect(await run(), 1);
        expect(saved.single.id, 1);
        expect(saved.single.summary, 'Hangout - noe sammy fernando');
        expect(
          saved.single.participantIds,
          unorderedEquals(['c_noe', 'c_other', 'c_sammy', 'c_fernando']),
        );

        expect(await run(), 0);
        expect(saved, hasLength(1));
      });

      test('re-links marker imports only when participants are missing',
          () async {
        final saved = <Interaction>[];
        Interaction markerImport(int id, List<String> participants) =>
            Interaction(
              id: id,
              occurredAt: DateTime(2025, 9, 23),
              summary: 'Dinner - Boba',
              medium: 'In Person',
              notes: 'Boba w/ noe sammy',
              participantIds: participants,
            );

        final fixed = await syncService.backfillImportedTitles(
          contacts: crew,
          loadInteractions: () async => [
            markerImport(3, const ['c_noe']),
            markerImport(4, const ['c_noe', 'c_sammy']),
          ],
          saveInteraction: (i) async => saved.add(i),
        );

        expect(fixed, 1);
        expect(saved.single.id, 3);
        expect(saved.single.summary, 'Dinner - Boba');
        expect(
            saved.single.participantIds, unorderedEquals(['c_noe', 'c_sammy']));
      });

      test('waits for contacts before marking the backfill done', () async {
        final saved = <Interaction>[];
        expect(
          await syncService.backfillImportedTitles(
            contacts: const [],
            loadInteractions: () async => [legacy()],
            saveInteraction: (i) async => saved.add(i),
          ),
          0,
        );
        expect(
          await syncService.backfillImportedTitles(
            contacts: crew,
            loadInteractions: () async => [legacy()],
            saveInteraction: (i) async => saved.add(i),
          ),
          1,
        );
      });
    });
  });
}
