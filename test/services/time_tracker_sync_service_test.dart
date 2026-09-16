import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';
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
      syncService = TimeTrackerSyncService(
        driveService: mockDriveService,
      );
    });

    test(
        'syncFromDrive parses candidates from newest file in Time Track folder',
        () async {
      final driveFile = drive.File()
        ..id = 'file_123'
        ..name = 'stt_records_automatic (4).csv'
        ..modifiedTime = DateTime.parse('2025-09-20 00:00:00Z');

      when(() => mockDriveService.findLatestFileInFolder(
            folderName: 'Time Track',
            namePrefix: 'stt_records_automatic',
          )).thenAnswer((_) async => driveFile);

      when(() => mockDriveService.downloadFileAsString('file_123'))
          .thenAnswer((_) async => sampleCsv);

      final candidates = await syncService.syncFromDrive(contacts: contacts);

      expect(candidates.length, 2);
      expect(candidates[0].activityName, 'Lunch');
      expect(candidates[1].activityName, 'Dinner');
      expect(syncService.stagingQueue.length, 2);
    });

    test(
        'deduplication ignores fingerprints that were already confirmed and imported',
        () async {
      final driveFile = drive.File()
        ..id = 'file_123'
        ..name = 'stt_records_automatic (4).csv';

      when(() => mockDriveService.findLatestFileInFolder(
            folderName: 'Time Track',
            namePrefix: 'stt_records_automatic',
          )).thenAnswer((_) async => driveFile);

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

    test('stagingQueue maintains candidates and allows updating or removing',
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
      expect(syncService.stagingQueue.first.summary, 'Morning Coffee w/ Abel');

      // Dismiss / remove candidate
      syncService.removeCandidates([candidate.fingerprint]);
      expect(syncService.stagingQueue, isEmpty);
    });
  });
}
