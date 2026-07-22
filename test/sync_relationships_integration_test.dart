import 'dart:convert';
import 'dart:io';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Relationship sync integration', () {
    late Database db;
    late DBHelper dbHelper;
    late Directory syncDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      dbHelper = DBHelper();
      DBHelper.setDatabaseForTest(db);
      await dbHelper.createSchemaForTest(db);
      syncDir = await Directory.systemTemp.createTemp('relationship_sync_test');
    });

    tearDown(() async {
      await db.close();
      if (await syncDir.exists()) {
        await syncDir.delete(recursive: true);
      }
    });

    test('exports and imports relationships with contacts', () async {
      await dbHelper.insertContact(Contact(id: 'c1', firstName: 'Alice'));
      await dbHelper.insertContact(Contact(id: 'c2', firstName: 'Bob'));
      await dbHelper.upsertRelationship(
        Relationship(
          sourceContactId: 'c1',
          targetContactId: 'c2',
          type: 'Mentor',
          notes: 'Meets monthly',
        ),
      );

      final exportResult = await SyncCoordinator(
        dbHelper,
      ).exportChanges(syncDir);

      expect(exportResult.exportedCount, greaterThanOrEqualTo(3));

      final exportFile = await syncDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .singleWhere((file) => p.basename(file.path).endsWith('_data.json'));
      final payload =
          jsonDecode(await exportFile.readAsString()) as Map<String, dynamic>;

      expect(payload['contacts'], hasLength(2));
      expect(payload['relationships'], hasLength(1));

      await dbHelper.clearAllData();
      expect(await dbHelper.getContacts(), isEmpty);
      expect(await dbHelper.getAllRelationships(), isEmpty);

      await SyncCoordinator(dbHelper).importSyncData(payload);

      final restoredContacts = await dbHelper.getContacts();
      final restoredRelationships = await dbHelper.getAllRelationships();

      expect(
        restoredContacts.map((contact) => contact.id),
        containsAll(['c1', 'c2']),
      );
      expect(restoredRelationships, hasLength(1));
      expect(restoredRelationships.first.sourceContactId, 'c1');
      expect(restoredRelationships.first.targetContactId, 'c2');
      expect(restoredRelationships.first.type, 'Mentor');
      expect(restoredRelationships.first.notes, 'Meets monthly');
    });

    test(
      'does not duplicate relationships when sync payload is reimported',
      () async {
        final payload = {
          'version': 2,
          'deviceId': 'remote-device',
          'timestamp': DateTime(2024, 1, 1).toUtc().toIso8601String(),
          'integrityCheck': 'valid',
          'contacts': [
            Contact(id: 'c1', firstName: 'Alice').toMap(),
            Contact(id: 'c2', firstName: 'Bob').toMap(),
          ],
          'interactions': [],
          'prayerRequests': [],
          'prayerLists': [],
          'relationships': const [
            {
              'id': 42,
              'sourceContactId': 'c1',
              'targetContactId': 'c2',
              'type': 'Mentor',
              'notes': 'Meets monthly',
            },
          ],
        };

        final coordinator = SyncCoordinator(dbHelper);

        await coordinator.importSyncData(payload);
        await coordinator.importSyncData(payload);

        final relationships = await dbHelper.getAllRelationships();

        expect(relationships, hasLength(1));
        expect(relationships.first.sourceContactId, 'c1');
        expect(relationships.first.targetContactId, 'c2');
        expect(relationships.first.type, 'Mentor');
      },
    );

    test('importChanges imports relationship files once', () async {
      final payload = {
        'version': 2,
        'deviceId': 'remote-device',
        'timestamp': DateTime(2024, 1, 1).toUtc().toIso8601String(),
        'integrityCheck': 'valid',
        'contacts': [
          Contact(id: 'c1', firstName: 'Alice').toMap(),
          Contact(id: 'c2', firstName: 'Bob').toMap(),
        ],
        'interactions': [],
        'prayerRequests': [],
        'prayerLists': [],
        'relationships': const [
          {
            'id': 42,
            'sourceContactId': 'c1',
            'targetContactId': 'c2',
            'type': 'Mentor',
            'notes': 'Meets monthly',
          },
        ],
      };
      final syncFile = File(
        p.join(syncDir.path, 'remote_1704067200000_data.json'),
      );
      await syncFile.writeAsString(jsonEncode(payload));

      final coordinator = SyncCoordinator(dbHelper);

      final firstImport = await coordinator.importChanges(syncDir);
      final secondImport = await coordinator.importChanges(syncDir);

      final relationships = await dbHelper.getAllRelationships();

      expect(firstImport.importedCount, 1);
      expect(secondImport.importedCount, 0);
      expect(relationships, hasLength(1));
      expect(relationships.first.sourceContactId, 'c1');
      expect(relationships.first.targetContactId, 'c2');
    });

    test(
      'second export only includes relationships changed since the last export',
      () async {
        await dbHelper.insertContact(Contact(id: 'c1', firstName: 'Alice'));
        await dbHelper.insertContact(Contact(id: 'c2', firstName: 'Bob'));
        await dbHelper.upsertRelationship(
          Relationship(
            sourceContactId: 'c1',
            targetContactId: 'c2',
            type: 'Mentor',
          ),
        );

        final coordinator = SyncCoordinator(dbHelper);
        final firstExport = await coordinator.exportChanges(syncDir);
        expect(firstExport.exportedCount, greaterThanOrEqualTo(3));

        // Clear the first export file so the second export is easy to isolate.
        final firstFiles = await syncDir
            .list()
            .where((e) => e is File)
            .cast<File>()
            .where((f) => p.basename(f.path).endsWith('_data.json'))
            .toList();
        for (final f in firstFiles) {
          await f.delete();
        }

        // Nothing changed: the relationship shouldn't be resent.
        final secondExport = await coordinator.exportChanges(syncDir);
        expect(secondExport.exportedCount, 0);
        final filesAfterNoop = await syncDir
            .list()
            .where((e) => e is File)
            .cast<File>()
            .where((f) => p.basename(f.path).endsWith('_data.json'))
            .toList();
        expect(filesAfterNoop, isEmpty);
      },
    );

    test(
      'skips a relationship referencing a contact that has not been '
      'imported yet, without throwing',
      () async {
        await dbHelper.insertContact(Contact(id: 'c1', firstName: 'Alice'));

        final payload = {
          'version': 2,
          'deviceId': 'remote-device',
          'timestamp': DateTime(2024, 1, 1).toUtc().toIso8601String(),
          'integrityCheck': 'valid',
          'contacts': [],
          'interactions': [],
          'prayerRequests': [],
          'prayerLists': [],
          'relationships': const [
            {
              'sourceContactId': 'c1',
              'targetContactId': 'unknown-contact',
              'type': 'Friend',
            },
          ],
        };

        await SyncCoordinator(dbHelper).importSyncData(payload);

        final relationships = await dbHelper.getAllRelationships();
        expect(relationships, isEmpty);
      },
    );
  });
}
