import 'dart:convert';
import 'dart:io';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/services/export_service.dart';
import 'package:bnpb/services/import_service.dart';
import 'package:bnpb/services/reminder_coordinator.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:bnpb/services/sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Diagnosing Prayer List Sync and Export/Import', () {
    late DBHelper dbHelper;
    late Database dbA;
    late Database dbB;
    late Directory tempDir;
    late Directory syncDir;

    setUp(() async {
      dbHelper = DBHelper();
      tempDir = await Directory.systemTemp.createTemp('prayer_diag_test');
      syncDir = Directory(p.join(tempDir.path, 'shared_sync'));
      await syncDir.create();

      dbA = await databaseFactory.openDatabase(p.join(tempDir.path, 'devA.db'));
      dbB = await databaseFactory.openDatabase(p.join(tempDir.path, 'devB.db'));
      await dbHelper.createSchemaForTest(dbA);
      await dbHelper.createSchemaForTest(dbB);
      SharedPreferences.setMockInitialValues({});
      ReminderCoordinator.overrideForTest(_DummyReminderCoordinator());

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          return tempDir.path;
        },
      );
    });

    tearDown(() async {
      await dbA.close();
      await dbB.close();
      await tempDir.delete(recursive: true);
      ReminderCoordinator.resetTestOverride();
    });

    test(
        'Case 1: Sync between Device A and Device B when Device B already has default list',
        () async {
      // Setup Device A
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      final coordA = SyncCoordinator(dbHelper);

      final contactA = Contact(id: 'c-1', firstName: 'Alice');
      await dbHelper.insertContact(contactA);

      final listA = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await dbHelper.insertPrayerList(listA);
      await dbHelper.addContactToPrayerList(listA.id, 'c-1');

      // Setup Device B (Device B also created default "My Prayer List" independently)
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      final coordB = SyncCoordinator(dbHelper);

      final listB = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await dbHelper.insertPrayerList(listB);

      // Device A exports to syncDir
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      await coordA.exportChanges(syncDir);

      // Device B imports from syncDir
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      await coordB.importChanges(syncDir);

      // Now on Device B, what does getPrayerLists() return, and what is in lists.first?
      final listsOnB = await dbHelper.getPrayerLists();
      final firstListOnB = listsOnB.first;

      // Expect that on Device B, the user sees their contact on "My Prayer List"
      expect(firstListOnB.contactIds, contains('c-1'),
          reason: 'User expects "My Prayer List" on Device B to have c-1');
    });

    test('Case 2: Sync when contacts are added/removed on Device B', () async {
      // Setup Device A
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      final coordA = SyncCoordinator(dbHelper);

      final c1 = Contact(id: 'c-1', firstName: 'Alice');
      final c2 = Contact(id: 'c-2', firstName: 'Bob');
      await dbHelper.insertContact(c1);
      await dbHelper.insertContact(c2);

      final listA = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await dbHelper.insertPrayerList(listA);
      await dbHelper.addContactToPrayerList(listA.id, 'c-1');

      // Export A
      await coordA.exportChanges(syncDir);

      // Import to B (fresh B)
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      final coordB = SyncCoordinator(dbHelper);
      await coordB.importChanges(syncDir);

      var listsOnB = await dbHelper.getPrayerLists();
      expect(listsOnB, hasLength(1));
      expect(listsOnB.first.contactIds, contains('c-1'));

      // Device B adds c-2 to the list
      await dbHelper.addContactToPrayerList(listsOnB.first.id, 'c-2');

      // Wait a bit to ensure updatedAt differs
      await Future.delayed(const Duration(milliseconds: 10));

      // Device B exports
      await coordB.exportChanges(syncDir);

      // Device A imports
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      await coordA.importChanges(syncDir);

      final listsOnA = await dbHelper.getPrayerLists();
      expect(listsOnA.first.contactIds, containsAll(['c-1', 'c-2']));
    });

    test(
        'Case 3: Export/Import JSON round-trip via ExportService and ImportService',
        () async {
      // Setup Device A
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});

      final contactA = Contact(id: 'c-1', firstName: 'Alice');
      await dbHelper.insertContact(contactA);

      final listA = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await dbHelper.insertPrayerList(listA);
      await dbHelper.addContactToPrayerList(listA.id, 'c-1');

      // Export JSON from Device A
      final exportService = ExportService();
      final contactsA = await dbHelper.getContacts();
      final prayerListsA = await dbHelper.getPrayerLists();

      final exportFile = await exportService.exportJson(
        contactsA,
        ['firstName'],
        prayerLists: prayerListsA,
      );

      // Setup Device B (fresh or existing)
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});

      final importService = ImportService();
      final restored = await importService.importJsonExport(exportFile);

      final listsOnB = await dbHelper.getPrayerLists();
      expect(restored, equals(1));
      expect(listsOnB, isNotEmpty);
      expect(listsOnB.first.contactIds, contains('c-1'));
    });

    test('Case 4: Export JSON when prayerLists is NOT explicitly passed',
        () async {
      // Setup Device A
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});

      final contactA = Contact(id: 'c-1', firstName: 'Alice');
      await dbHelper.insertContact(contactA);

      final listA = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await dbHelper.insertPrayerList(listA);
      await dbHelper.addContactToPrayerList(listA.id, 'c-1');

      // Export JSON from Device A WITHOUT prayerLists parameter
      final exportService = ExportService();
      final contactsA = await dbHelper.getContacts();

      final exportFile = await exportService.exportJson(
        contactsA,
        ['firstName'],
      );

      // Read exported JSON content to check if prayerLists was included
      final jsonContent = await exportFile.readAsString();
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      expect(data['prayerLists'], isNotNull);

      // Import to Device B
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});

      final importService = ImportService();
      await importService.importJsonExport(exportFile);

      final listsOnB = await dbHelper.getPrayerLists();
      expect(listsOnB, isNotEmpty);
      expect(listsOnB.first.contactIds, contains('c-1'));
    });

    test(
        'Case 5: What if exported JSON has no version (legacy) or imported via legacy path',
        () async {
      // Setup Device A
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});

      final contactA = Contact(id: 'c-1', firstName: 'Alice');
      await dbHelper.insertContact(contactA);

      final listA = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await dbHelper.insertPrayerList(listA);
      await dbHelper.addContactToPrayerList(listA.id, 'c-1');

      // Construct legacy format JSON (no version: 2, no interactions key)
      final legacyMap = {
        'contacts': [contactA.toMap()],
        'prayerLists': [
          {
            'id': listA.id,
            'name': listA.name,
            'description': listA.description,
            'contactIds': ['c-1'],
          }
        ]
      };

      final legacyFile = File(p.join(tempDir.path, 'legacy.json'));
      await legacyFile.writeAsString(jsonEncode(legacyMap));

      // Import to Device B
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});

      final importService = ImportService();
      await importService.importJsonExport(legacyFile);

      final listsOnB = await dbHelper.getPrayerLists();
      expect(listsOnB, isNotEmpty);
      expect(listsOnB.first.contactIds, contains('c-1'));
    });

    test('Case 6: Legacy duplicate reconciliation in getPrayerLists()',
        () async {
      DBHelper.setDatabaseForTest(dbA);

      final c1 = Contact(id: 'c-1', firstName: 'Alice');
      final c2 = Contact(id: 'c-2', firstName: 'Bob');
      await dbHelper.insertContact(c1);
      await dbHelper.insertContact(c2);

      // Directly insert two duplicate rows with legacy UUIDs into the database
      final oldList1 = PrayerList(
        id: 'legacy-uuid-1',
        name: 'My Prayer List',
        description: 'First list',
      );
      final oldList2 = PrayerList(
        id: 'legacy-uuid-2',
        name: 'my prayer list', // different case
        description: 'Second list',
      );
      await dbHelper.insertPrayerList(oldList1);
      await dbHelper.addContactToPrayerList('legacy-uuid-1', 'c-1');

      await dbHelper.insertPrayerList(oldList2);
      await dbHelper.addContactToPrayerList('legacy-uuid-2', 'c-2');

      // Calling getPrayerLists() should self-heal and consolidate
      final reconciledLists = await dbHelper.getPrayerLists();
      expect(reconciledLists, hasLength(1));
      expect(reconciledLists.first.id, equals(PrayerList.defaultListId));
      expect(reconciledLists.first.contactIds, containsAll(['c-1', 'c-2']));
    });

    test('Case 7: Sync between Device A and Device B with legacy random UUIDs',
        () async {
      // Setup Device A with legacy-uuid-A
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      final coordA = SyncCoordinator(dbHelper);

      final c1 = Contact(id: 'c-1', firstName: 'Alice');
      final c2 = Contact(id: 'c-2', firstName: 'Bob');
      await dbHelper.insertContact(c1);
      await dbHelper.insertContact(c2);

      final listA = PrayerList(
        id: 'legacy-uuid-A',
        name: 'My Prayer List',
      );
      await dbHelper.insertPrayerList(listA);
      await dbHelper.addContactToPrayerList('legacy-uuid-A', 'c-1');

      // Setup Device B with legacy-uuid-B
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      final coordB = SyncCoordinator(dbHelper);

      final listB = PrayerList(
        id: 'legacy-uuid-B',
        name: 'My Prayer List',
      );
      await dbHelper.insertPrayerList(listB);
      await dbHelper.addContactToPrayerList('legacy-uuid-B', 'c-2');

      // Device A exports to syncDir
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      await coordA.exportChanges(syncDir);

      // Device B imports from syncDir
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      await coordB.importChanges(syncDir);

      final listsOnB = await dbHelper.getPrayerLists();
      expect(listsOnB, hasLength(1));
      expect(listsOnB.first.id, equals(PrayerList.defaultListId));
      expect(listsOnB.first.contactIds, containsAll(['c-1', 'c-2']));
    });

    test('Case 8: Sync deletion of prayer list', () async {
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      final coordA = SyncCoordinator(dbHelper);

      final listA = PrayerList.create(name: 'List to Delete');
      await dbHelper.insertPrayerList(listA);

      await coordA.exportChanges(syncDir);

      // Import to B
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      final coordB = SyncCoordinator(dbHelper);
      await coordB.importChanges(syncDir);

      var listsOnB = await dbHelper.getPrayerLists();
      expect(listsOnB.any((l) => l.name == 'List to Delete'), isTrue);

      // Device A deletes the list
      DBHelper.setDatabaseForTest(dbA);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-A'});
      await dbHelper.deletePrayerList(listA.id);

      await Future.delayed(const Duration(milliseconds: 10));
      await coordA.exportChanges(syncDir);

      // Device B imports the deletion
      DBHelper.setDatabaseForTest(dbB);
      SharedPreferences.setMockInitialValues({'sync_device_id': 'device-B'});
      await coordB.importChanges(syncDir);

      listsOnB = await dbHelper.getPrayerLists();
      expect(listsOnB.any((l) => l.name == 'List to Delete'), isFalse);
    });

    test(
        'Case 9: ensureDefaultPrayerList() provisions default list idempotently',
        () async {
      DBHelper.setDatabaseForTest(dbA);

      // On a fresh database, ensureDefaultPrayerList should create default_prayer_list
      final initialList = await dbHelper.ensureDefaultPrayerList();
      expect(initialList.id, equals(PrayerList.defaultListId));
      expect(initialList.name, equals(PrayerList.defaultListName));

      // Repeated calls must return the same list without creating duplicates
      final secondCall = await dbHelper.ensureDefaultPrayerList();
      expect(secondCall.id, equals(PrayerList.defaultListId));

      final allLists = await dbHelper.getPrayerLists();
      expect(allLists, hasLength(1));
      expect(allLists.first.id, equals(PrayerList.defaultListId));
    });

    test('Case 10: importJsonExport notifies SyncService.onSyncComplete',
        () async {
      DBHelper.setDatabaseForTest(dbA);
      final contactA = Contact(id: 'c-1', firstName: 'Alice');
      await dbHelper.insertContact(contactA);

      final exportService = ExportService();
      final exportFile =
          await exportService.exportJson([contactA], ['firstName']);

      DBHelper.setDatabaseForTest(dbB);
      final importService = ImportService();

      bool syncNotified = false;
      final sub = SyncService().onSyncComplete.listen((_) {
        syncNotified = true;
      });

      await importService.importJsonExport(exportFile);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(syncNotified, isTrue);
      await sub.cancel();
    });
  });
}

class _DummyReminderCoordinator extends ReminderCoordinator {
  _DummyReminderCoordinator() : super.testHarness();
  @override
  Future<void> refreshAllContacts() async {}
}
