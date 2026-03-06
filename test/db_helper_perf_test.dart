import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'DBHelper.getContacts performance (revised)',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      final dbHelper = DBHelper();

      DBHelper.setDatabaseForTest(db);
      await dbHelper.createSchemaForTest(db);

      final int count = 2000;
      debugPrint('Inserting $count contacts...');

      final batch = db.batch();
      for (int i = 0; i < count; i++) {
        final contactId = const Uuid().v4();
        final now = DateTime.now().toIso8601String();

        batch.insert('contacts', {
          'id': contactId,
          'firstName': 'Test',
          'lastName': '$i',
          'updatedAt': now,
        });
        batch.insert('contact_tags', {'contactId': contactId, 'tag': 'Tag $i'});

        // Explicit interaction ID
        final interactionId = i + 1;
        batch.insert('interactions', {
          'id': interactionId,
          'syncId': const Uuid().v4(),
          'occurredAt': now,
          'summary': 'Interaction $i',
          'medium': 'in_person',
          'updatedAt': now,
        });

        batch.insert('interaction_participants', {
          'interactionId': interactionId,
          'contactId': contactId,
        });
      }
      await batch.commit(noResult: true);

      debugPrint('Finished inserting. Fetching all...');

      final stopwatch = Stopwatch()..start();
      final fetched = await dbHelper.getContacts();
      debugPrint(
        'Fetched ${fetched.length} contacts in ${stopwatch.elapsedMilliseconds}ms',
      );

      expect(fetched.length, greaterThanOrEqualTo(count));

      final first = fetched.first;
      expect(first.tags, isNotEmpty, reason: 'Tags should be fetched');
      expect(
        first.interactions,
        isNotEmpty,
        reason: 'Interactions should be fetched',
      );
      expect(
        first.interactions.first.summary,
        contains('Interaction'),
        reason: 'Interaction summary should match',
      );

      await db.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
