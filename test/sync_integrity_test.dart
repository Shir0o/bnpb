import 'dart:convert';
import 'dart:io';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'repositories/mock_db_helper.dart';

class IntegritySpyDBHelper extends MockDBHelper {
  late Database _db;
  int upsertCount = 0;

  Future<void> init() async {
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createSchema(_db);
  }

  @override
  Future<Database> get database async => _db;

  @override
  Future<void> upsertContactFromSync(DatabaseExecutor txn, Contact contact,
      {required bool isUpdate}) async {
    upsertCount++;
  }

  @override
  Future<Contact?> getContactById(String id) async => null;
  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      [];

  Future<void> _createSchema(Database db) async {
    // Minimal schema for SyncCoordinator
    await db.execute('''
      CREATE TABLE interactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        syncId TEXT NOT NULL UNIQUE,
        occurredAt TEXT NOT NULL,
        summary TEXT NOT NULL,
        medium TEXT NOT NULL,
        location TEXT,
        attachments TEXT,
        markForPrayer INTEGER NOT NULL DEFAULT 0,
        followUpAt TEXT,
        durationMinutes INTEGER,
        notes TEXT,
        updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
        deletedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE prayer_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        syncId TEXT NOT NULL UNIQUE,
        contactId TEXT NOT NULL,
        interactionId INTEGER,
        description TEXT NOT NULL,
        status TEXT NOT NULL,
        requestedAt TEXT NOT NULL,
        answeredAt TEXT,
        category TEXT,
        reflectionNotes TEXT,
        updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
        deletedAt TEXT
      )
    ''');

    await db.execute('''
       CREATE TABLE prayer_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        color TEXT,
        displayIndex INTEGER NOT NULL DEFAULT 0,
        updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
        deletedAt TEXT
      )
    ''');

    await db.execute('''
       CREATE TABLE prayer_list_members (
        listId TEXT NOT NULL,
        contactId TEXT NOT NULL,
        PRIMARY KEY(listId, contactId)
      )
    ''');

    await db.execute('''
       CREATE TABLE interaction_participants (
        interactionId INTEGER NOT NULL,
        contactId TEXT NOT NULL,
        PRIMARY KEY(interactionId, contactId)
      )
    ''');
  }
}

void main() {
  late Directory tempDir;
  late IntegritySpyDBHelper fakeDb;
  late SyncCoordinator coordinator;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('integrity_test');
    fakeDb = IntegritySpyDBHelper();
    await fakeDb.init();

    SharedPreferences.setMockInitialValues({});
    coordinator = SyncCoordinator(fakeDb);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    // ignore: invalid_use_of_protected_member
    await fakeDb.database.then((db) => db.close());
  });

  test('importChanges skips empty files', () async {
    final emptyFile = File('${tempDir.path}/empty_data.json');
    await emptyFile.writeAsString('');

    final result = await coordinator.importChanges(tempDir);
    expect(result.importedCount, 0);
  });

  test('importChanges skips invalid JSON files', () async {
    final invalidFile = File('${tempDir.path}/invalid_data.json');
    await invalidFile
        .writeAsString('{ "version": 1, "contacts": ['); // Incomplete

    final result = await coordinator.importChanges(tempDir);
    expect(result.importedCount, 0);
  });

  test('importChanges skips JSON without version key', () async {
    final noVersionFile = File('${tempDir.path}/no_version_data.json');
    await noVersionFile.writeAsString('{"contacts": []}');

    final result = await coordinator.importChanges(tempDir);
    expect(result.importedCount, 0);
  });

  test('importChanges processes valid files', () async {
    final validFile = File('${tempDir.path}/valid_data.json');

    final contact =
        Contact(id: 'c1', firstName: 'Test', updatedAt: DateTime.now());

    await validFile.writeAsString(jsonEncode({
      'version': 1,
      'contacts': [contact.toMap()], // Provide 1 contact to trigger upsertCount
      'interactions': [],
      'prayerRequests': [],
      'prayerLists': []
    }));

    final result = await coordinator.importChanges(tempDir);

    // Result count depends on number of files processed, not items imported?
    // SyncCoordinator calls: importCount++; per file.
    // If it succeeds, count should be 1.
    expect(result.importedCount, 1);

    // Verify our spy was called
    expect(fakeDb.upsertCount, 1);
  });
}
