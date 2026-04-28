import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/services/export_service.dart';
import 'package:bnpb/services/import_service.dart';
import 'package:bnpb/services/reminder_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

/// This script demonstrates and validates the prayer list export/import behavior.
/// It uses sqflite_ffi to run in a standalone environment or via flutter test.
void main() async {
  // Ensure we can use print during tests if run via flutter test
  // ignore: avoid_print
  print('--- Prayer List Export/Import Manual Test ---');

  // Initialize FFI for standalone execution
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Set up mock SharedPreferences for SyncCoordinator device ID logic
  SharedPreferences.setMockInitialValues({});

  // Override ReminderCoordinator to avoid notification initialization errors
  ReminderCoordinator.overrideForTest(_DummyReminderCoordinator());

  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  final dbHelper = DBHelper();
  DBHelper.setDatabaseForTest(db);
  await dbHelper.createSchemaForTest(db);

  // ignore: avoid_print
  print('1. Creating test data...');
  final contactId = const Uuid().v4();
  await dbHelper
      .insertContact(Contact(id: contactId, firstName: 'Manual Test Contact'));

  const listId = 'manual-list-999';
  final list = PrayerList(
    id: listId,
    name: 'Manual Test List',
    description: 'Created for manual verification',
    contactIds: [contactId],
    color: '0xFFFF5733',
  );
  await dbHelper.insertPrayerList(list);

  // ignore: avoid_print
  print('2. Exporting to JSON...');
  final contacts = await dbHelper.getContacts();
  final prayerLists = await dbHelper.getPrayerLists();

  final payload = await ExportService().buildFullExportPayload(
    contacts,
    ['firstName'],
    prayerLists: prayerLists,
  );

  final jsonStr = jsonEncode(payload);
  // ignore: avoid_print
  print('Exported JSON Payload:');
  // ignore: avoid_print
  print(jsonStr);

  // ignore: avoid_print
  print('\n3. Clearing database...');
  await dbHelper.clearAllData();
  final count = (await dbHelper.getPrayerLists()).length;
  // ignore: avoid_print
  print('Prayer lists in DB after clear: $count');

  // ignore: avoid_print
  print('\n4. Importing from JSON...');
  final tempDir = Directory.systemTemp.createTempSync();
  final tempFile = File(p.join(tempDir.path, 'manual_test_export.json'));
  await tempFile.writeAsString(jsonStr);

  await ImportService().importJsonExport(tempFile);
  // ignore: avoid_print
  print('Import complete.');

  // ignore: avoid_print
  print('\n5. Verifying restored data...');
  final restoredLists = await dbHelper.getPrayerLists();
  if (restoredLists.isEmpty) {
    // ignore: avoid_print
    print('FAILURE: No prayer lists restored!');
  } else {
    final restored = restoredLists.first;
    // ignore: avoid_print
    print('Restored Prayer List:');
    // ignore: avoid_print
    print('  ID: ${restored.id}');
    // ignore: avoid_print
    print('  Name: ${restored.name}');
    // ignore: avoid_print
    print('  Members: ${restored.contactIds}');

    if (restored.id == listId && restored.contactIds.contains(contactId)) {
      // ignore: avoid_print
      print('SUCCESS: Prayer list restored correctly with members.');
    } else {
      // ignore: avoid_print
      print('FAILURE: Data mismatch in restored prayer list.');
    }
  }

  await db.close();
  tempDir.deleteSync(recursive: true);
  ReminderCoordinator.resetTestOverride();
  // ignore: avoid_print
  print('\n--- Test Finished ---');
}

class _DummyReminderCoordinator extends ReminderCoordinator {
  _DummyReminderCoordinator() : super.testHarness();
  @override
  Future<void> refreshAllContacts() async {}
}
