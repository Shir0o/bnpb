import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/db/daos/interaction_dao.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
      'InteractionDao.deDuplicateInteractions finds, merges, and soft-deletes duplicates',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    final dbHelper = DBHelper();
    DBHelper.setDatabaseForTest(db);
    await dbHelper.createSchemaForTest(db);

    final dao = InteractionDao(dbHelper);
    final contactId1 = const Uuid().v4();
    final contactId2 = const Uuid().v4();

    // Insert mock contacts for foreign keys
    await db.insert('contacts', {
      'id': contactId1,
      'firstName': 'Contact 1',
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await db.insert('contacts', {
      'id': contactId2,
      'firstName': 'Contact 2',
      'updatedAt': DateTime.now().toIso8601String(),
    });

    final occurredAt = DateTime(2026, 6, 1, 10, 0, 0);

    // Duplicate 1: Oldest
    final intId1 = await db.insert('interactions', {
      'syncId': 'sync-id-1',
      'occurredAt': occurredAt.toIso8601String(),
      'summary': 'Lunch Meeting',
      'medium': 'in_person',
      'location': 'Cafe A',
      'attachments': '[]',
      'markForPrayer': 0,
      'durationMinutes': 30,
      'notes': 'Discussion on project A',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await db.insert('interaction_participants', {
      'interactionId': intId1,
      'contactId': contactId1,
    });

    // Duplicate 2: Newer, different sync ID, different participant, marked for prayer, different notes
    final intId2 = await db.insert('interactions', {
      'syncId': 'sync-id-2',
      'occurredAt': occurredAt.toIso8601String(),
      'summary': '  lunch meeting  ', // whitespaces & case check
      'medium': 'in_person',
      'location': 'Cafe B',
      'attachments':
          '[{"uri":"http://example.com/doc.pdf","source":"cloud","label":"Doc"}]',
      'markForPrayer': 1,
      'durationMinutes': 45,
      'notes': 'Follow up on project B',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await db.insert('interaction_participants', {
      'interactionId': intId2,
      'contactId': contactId2,
    });

    // Run de-duplication
    final mergedCount = await dao.deDuplicateInteractions();
    expect(mergedCount, 1);

    // Verify primary (intId1) is updated
    final primaryRows =
        await db.query('interactions', where: 'id = ?', whereArgs: [intId1]);
    expect(primaryRows.length, 1);
    final primaryMap = primaryRows.first;

    // Check soft-delete status
    expect(primaryMap['deletedAt'], isNull);
    expect(primaryMap['markForPrayer'], 1); // Or-ed
    expect(primaryMap['durationMinutes'], 45); // Max duration or updated
    expect(primaryMap['notes'], contains('Discussion on project A'));
    expect(primaryMap['notes'], contains('Follow up on project B'));

    // Check participants of primary are merged
    final participantRows = await db.query(
      'interaction_participants',
      where: 'interactionId = ?',
      whereArgs: [intId1],
    );
    final participantIds =
        participantRows.map((r) => r['contactId'] as String).toSet();
    expect(participantIds, contains(contactId1));
    expect(participantIds, contains(contactId2));

    // Verify Duplicate 2 is soft-deleted
    final dupRows =
        await db.query('interactions', where: 'id = ?', whereArgs: [intId2]);
    expect(dupRows.length, 1);
    expect(dupRows.first['deletedAt'], isNotNull);

    await db.close();
  });
}
