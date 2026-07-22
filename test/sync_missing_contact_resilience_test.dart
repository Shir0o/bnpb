import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the defensive contact-existence checks added to
/// [SyncCoordinator]'s merge methods: a sync file referencing a contact
/// that hasn't been imported yet (e.g. because it fell off a paginated
/// Drive listing) should have that one reference skipped, rather than
/// throwing a FOREIGN KEY error that aborts the rest of the file.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Sync missing-contact resilience', () {
    late Database db;
    late DBHelper dbHelper;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      dbHelper = DBHelper();
      DBHelper.setDatabaseForTest(db);
      await dbHelper.createSchemaForTest(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'imports an interaction while dropping an unknown participant',
      () async {
        await dbHelper.insertContact(Contact(id: 'known', firstName: 'Alice'));

        final interaction = Interaction(
          occurredAt: DateTime.now().toUtc(),
          summary: 'Coffee chat',
          medium: 'In-person',
          participantIds: const ['known', 'unknown-contact'],
        );

        final payload = {
          'version': 2,
          'deviceId': 'remote-device',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'integrityCheck': 'valid',
          'contacts': [],
          'interactions': [interaction.toMap(includeId: false)],
          'prayerRequests': [],
          'prayerLists': [],
          'relationships': [],
        };

        await SyncCoordinator(dbHelper).importSyncData(payload);

        final imported = await dbHelper.getInteractions(includeDeleted: true);
        expect(imported, hasLength(1));
        expect(imported.first.participantIds, ['known']);
      },
    );

    test(
      'skips a prayer request whose contact is unknown but still imports '
      'the rest of the file',
      () async {
        await dbHelper.insertContact(Contact(id: 'known', firstName: 'Alice'));

        final skippedPrayer = PrayerRequest(
          participantIds: const ['unknown-contact'],
          description: 'Pray for travel safety',
          status: PrayerRequestStatus.pending,
          requestedAt: DateTime.now().toUtc(),
        );
        final validPrayer = PrayerRequest(
          participantIds: const ['known'],
          description: 'Pray for healing',
          status: PrayerRequestStatus.pending,
          requestedAt: DateTime.now().toUtc(),
        );

        final payload = {
          'version': 2,
          'deviceId': 'remote-device',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'integrityCheck': 'valid',
          'contacts': [],
          'interactions': [],
          'prayerRequests': [
            skippedPrayer.toMap(includeId: false),
            validPrayer.toMap(includeId: false),
          ],
          'prayerLists': [],
          'relationships': [],
        };

        await SyncCoordinator(dbHelper).importSyncData(payload);

        final imported = await dbHelper.getPrayerRequests(includeDeleted: true);
        expect(imported, hasLength(1));
        expect(imported.first.description, 'Pray for healing');
      },
    );
  });
}
