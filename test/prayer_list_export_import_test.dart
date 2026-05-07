import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/services/export_service.dart';
import 'package:bnpb/services/import_service.dart';
import 'package:bnpb/services/reminder_coordinator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Prayer List Export/Import Round-trip Integration', () {
    late Database db;
    late DBHelper dbHelper;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      dbHelper = DBHelper();
      DBHelper.setDatabaseForTest(db);
      await dbHelper.createSchemaForTest(db);
      SharedPreferences.setMockInitialValues({});
      ReminderCoordinator.overrideForTest(_DummyReminderCoordinator());
    });

    tearDown(() async {
      ReminderCoordinator.resetTestOverride();
      await db.close();
    });

    test('Successfully exports and imports prayer lists with members', () async {
      // 1. Create a contact
      final contactId = const Uuid().v4();
      final contact = Contact(
        id: contactId,
        firstName: 'Alice',
        lastName: 'Test',
      );
      await dbHelper.insertContact(contact);

      // 2. Create a prayer list containing that contact
      final prayerList = PrayerList(
        id: 'list-123',
        name: 'Morning Prayer',
        description: 'Testing export/import',
        contactIds: [contactId],
        color: '0xFF4287F5',
      );
      await dbHelper.insertPrayerList(prayerList);

      // Verify the list exists in the database
      final listsBefore = await dbHelper.getPrayerLists();
      expect(listsBefore, hasLength(1));
      expect(listsBefore.first.name, 'Morning Prayer');
      expect(listsBefore.first.contactIds, contains(contactId));

      // 3. Export to JSON (using buildFullExportPayload which UI uses for backups)
      final exportService = ExportService();
      final contacts = await dbHelper.getContacts();
      final prayerLists = await dbHelper.getPrayerLists();

      final payload = await exportService.buildFullExportPayload(contacts, [
        'firstName',
        'lastName',
      ], prayerLists: prayerLists);

      final jsonStr = jsonEncode(payload);

      // 4. Wipe the database to simulate restoring to a clean state
      await dbHelper.clearAllData();
      final listsAfterClear = await dbHelper.getPrayerLists();
      expect(listsAfterClear, isEmpty);
      expect(await dbHelper.getContacts(), isEmpty);

      // 5. Import from the JSON string
      // We need to write to a temp file as importJsonExport takes a File
      final tempDir = Directory.systemTemp.createTempSync();
      final tempFile = File(p.join(tempDir.path, 'test_restore.json'));
      await tempFile.writeAsString(jsonStr);

      final importService = ImportService();
      final restoredCount = await importService.importJsonExport(tempFile);

      expect(restoredCount, 1, reason: 'Should have restored 1 contact');

      // 6. Final Verification: Data should be back exactly as it was
      final restoredLists = await dbHelper.getPrayerLists();
      expect(restoredLists, hasLength(1));

      final restoredList = restoredLists.first;
      expect(restoredList.id, 'list-123');
      expect(restoredList.name, 'Morning Prayer');
      expect(restoredList.description, 'Testing export/import');
      expect(restoredList.color, '0xFF4287F5');
      expect(restoredList.contactIds, contains(contactId));

      final restoredContacts = await dbHelper.getContacts();
      expect(restoredContacts, hasLength(1));
      expect(restoredContacts.first.id, contactId);
      expect(restoredContacts.first.firstName, 'Alice');

      // Cleanup
      tempDir.deleteSync(recursive: true);
    });
  });
}

class _DummyReminderCoordinator extends ReminderCoordinator {
  _DummyReminderCoordinator() : super.testHarness();
  @override
  Future<void> refreshAllContacts() async {}
}
