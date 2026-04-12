import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/db/daos/prayer_request_dao.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('PrayerRequestDao.replacePrayerRequestsForContact soft deletes old requests', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    final dbHelper = DBHelper();
    DBHelper.setDatabaseForTest(db);
    await dbHelper.createSchemaForTest(db);

    final dao = PrayerRequestDao(dbHelper);
    final contactId = const Uuid().v4();

    // Ensure contact exists for foreign key
    await db.insert('contacts', {
      'id': contactId,
      'firstName': 'Test',
      'updatedAt': DateTime.now().toIso8601String(),
    });

    // 1. Setup initial prayer requests
    int id1 = -1;
    int id2 = -1;
    await db.transaction((txn) async {
      id1 = await txn.insert('prayer_requests', {
        'syncId': const Uuid().v4(),
        'contactId': contactId,
        'description': 'Request 1',
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.insert('prayer_request_participants', {
        'prayerRequestId': id1,
        'contactId': contactId,
      });

      id2 = await txn.insert('prayer_requests', {
        'syncId': const Uuid().v4(),
        'contactId': contactId,
        'description': 'Request 2',
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.insert('prayer_request_participants', {
        'prayerRequestId': id2,
        'contactId': contactId,
      });
    });

    // Verify they exist and are not deleted
    final checkBefore = await db.query('prayer_requests', where: 'deletedAt IS NULL');
    expect(checkBefore.length, 2);

    // 2. Call replacePrayerRequestsForContact with ONLY request 1
    final contact = Contact(
      id: contactId,
      firstName: 'Test',
      lastName: 'User',
      prayerRequests: [
        PrayerRequest(
          id: id1,
          participantIds: [contactId],
          description: 'Request 1',
          status: PrayerRequestStatus.pending,
          requestedAt: DateTime.now(),
        ),
      ],
    );

    await db.transaction((txn) async {
      await dao.replacePrayerRequestsForContact(txn, contact);
    });

    // 3. Verify request 2 is soft deleted
    final request2 = await db.query('prayer_requests', where: 'id = ?', whereArgs: [id2]);
    expect(request2.first['deletedAt'], isNotNull);
    expect(request2.first['updatedAt'], isNotNull);

    // Verify request 1 is NOT soft deleted
    final request1 = await db.query('prayer_requests', where: 'id = ?', whereArgs: [id1]);
    expect(request1.first['deletedAt'], isNull);

    await db.close();
  });
}
