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
        const Relationship(
          sourceContactId: 'c1',
          targetContactId: 'c2',
          type: 'Mentor',
          notes: 'Meets monthly',
        ),
      );

      final exportResult = await SyncCoordinator(dbHelper).exportChanges(
        syncDir,
      );

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

      expect(restoredContacts.map((contact) => contact.id),
          containsAll(['c1', 'c2']));
      expect(restoredRelationships, hasLength(1));
      expect(restoredRelationships.first.sourceContactId, 'c1');
      expect(restoredRelationships.first.targetContactId, 'c2');
      expect(restoredRelationships.first.type, 'Mentor');
      expect(restoredRelationships.first.notes, 'Meets monthly');
    });
  });
}
