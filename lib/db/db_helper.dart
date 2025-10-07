import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/prayer_request.dart';
import '../models/relationship.dart';

class DBHelper {
  static const _dbName = 'contacts.db';
  static const _dbVersion = 5;

  static final DBHelper _instance = DBHelper._();
  static Database? _database;

  DBHelper._();

  factory DBHelper() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        firstName TEXT,
        middleName TEXT,
        lastName TEXT NULL,
        nickname TEXT,
        location TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE contact_methods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contactId TEXT,
        type TEXT,
        value TEXT,
        label TEXT,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE contact_tags (
        contactId TEXT,
        tag TEXT,
        PRIMARY KEY(contactId, tag),
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE meet_contexts (
        contactId TEXT PRIMARY KEY,
        metThroughId TEXT,
        firstMeetingNotes TEXT,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE,
        FOREIGN KEY(metThroughId) REFERENCES contacts(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE interactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contactId TEXT NOT NULL,
        occurredAt TEXT NOT NULL,
        summary TEXT NOT NULL,
        medium TEXT NOT NULL,
        location TEXT,
        attachments TEXT,
        markForPrayer INTEGER NOT NULL DEFAULT 0,
        followUpAt TEXT,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE relationships (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sourceContactId TEXT NOT NULL,
        targetContactId TEXT NOT NULL,
        type TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY(sourceContactId) REFERENCES contacts(id) ON DELETE CASCADE,
        FOREIGN KEY(targetContactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE prayer_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contactId TEXT NOT NULL,
        interactionId INTEGER,
        description TEXT NOT NULL,
        status TEXT NOT NULL,
        requestedAt TEXT NOT NULL,
        answeredAt TEXT,
        category TEXT,
        reflectionNotes TEXT,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE,
        FOREIGN KEY(interactionId) REFERENCES interactions(id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE contacts ADD COLUMN nickname TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS contact_methods (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          contactId TEXT,
          type TEXT,
          value TEXT,
          label TEXT,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS contact_tags (
          contactId TEXT,
          tag TEXT,
          PRIMARY KEY(contactId, tag),
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS meet_contexts (
          contactId TEXT PRIMARY KEY,
          metThroughId TEXT,
          firstMeetingNotes TEXT,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE,
          FOREIGN KEY(metThroughId) REFERENCES contacts(id) ON DELETE SET NULL
        )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS relationships (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sourceContactId TEXT NOT NULL,
          targetContactId TEXT NOT NULL,
          type TEXT NOT NULL,
          notes TEXT,
          FOREIGN KEY(sourceContactId) REFERENCES contacts(id) ON DELETE CASCADE,
          FOREIGN KEY(targetContactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS interactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          contactId TEXT NOT NULL,
          occurredAt TEXT NOT NULL,
          summary TEXT NOT NULL,
          medium TEXT NOT NULL,
          location TEXT,
          attachments TEXT,
          markForPrayer INTEGER NOT NULL DEFAULT 0,
          followUpAt TEXT,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');

      final legacyRows = await db.query('contacts', columns: ['id', 'history']);
      for (final row in legacyRows) {
        final contactId = row['id'] as String;
        final historyJson = row['history'] as String?;
        if (historyJson == null || historyJson.isEmpty) {
          continue;
        }

        final decoded = jsonDecode(historyJson) as List<dynamic>;
        for (final entry in decoded) {
          final entryMap = Map<String, dynamic>.from(
            entry as Map<String, dynamic>,
          );
          final summary = (entryMap['detail'] ?? '').toString();
          if (summary.isEmpty) continue;
          final occurredAt = entryMap['date'] as String? ??
              DateTime.now().toIso8601String();

          await db.insert('interactions', {
            'contactId': contactId,
            'occurredAt': occurredAt,
            'summary': summary,
            'medium': 'unspecified',
            'attachments': jsonEncode([]),
          });
        }
      }

      await db.execute('UPDATE contacts SET history = NULL');
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS prayer_requests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          contactId TEXT NOT NULL,
          interactionId INTEGER,
          description TEXT NOT NULL,
          status TEXT NOT NULL,
          requestedAt TEXT NOT NULL,
          answeredAt TEXT,
          category TEXT,
          reflectionNotes TEXT,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE,
          FOREIGN KEY(interactionId) REFERENCES interactions(id) ON DELETE SET NULL
        )
      ''');
    }
  }

  // -------------------------------------------------------------
  // CONTACTS METHODS
  // -------------------------------------------------------------

  /// Insert or replace a [Contact] in the database.
  Future<void> insertContact(Contact contact) async {
    final db = await database;

    await db.transaction((txn) async {
      await _upsertContactRow(txn, contact, isUpdate: false);
    });
  }

  Future<void> _upsertContactRow(
    DatabaseExecutor txn,
    Contact contact, {
    required bool isUpdate,
  }) async {
    final baseMap = <String, dynamic>{
      'id': contact.id,
      'firstName': contact.firstName,
      'middleName': contact.middleName,
      'lastName': contact.lastName,
      'nickname': contact.nickname,
      'location': contact.location,
    };

    if (isUpdate) {
      await txn.update(
        'contacts',
        baseMap,
        where: 'id = ?',
        whereArgs: [contact.id],
      );
    } else {
      await txn.insert(
        'contacts',
        baseMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await _upsertMeetContext(txn, contact);
    await _replaceContactMethods(txn, contact);
    await _replaceContactTags(txn, contact);

    if (contact.prayerRequests.isNotEmpty) {
      await _replacePrayerRequests(txn, contact);
    }
  }

  Future<void> _upsertMeetContext(
    DatabaseExecutor txn,
    Contact contact,
  ) async {
    final hasContext = (contact.metThroughId != null &&
            contact.metThroughId!.isNotEmpty) ||
        (contact.firstMeetingNotes != null &&
            contact.firstMeetingNotes!.isNotEmpty);

    if (!hasContext) {
      await txn.delete(
        'meet_contexts',
        where: 'contactId = ?',
        whereArgs: [contact.id],
      );
      return;
    }

    await txn.insert(
      'meet_contexts',
      {
        'contactId': contact.id,
        'metThroughId': contact.metThroughId,
        'firstMeetingNotes': contact.firstMeetingNotes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _replaceContactMethods(
    DatabaseExecutor txn,
    Contact contact,
  ) async {
    await txn.delete(
      'contact_methods',
      where: 'contactId = ?',
      whereArgs: [contact.id],
    );

    for (final method in contact.contactMethods) {
      if (method.value.isEmpty) continue;
      await txn.insert('contact_methods', {
        'contactId': contact.id,
        'type': method.type,
        'value': method.value,
        'label': method.label,
      });
    }
  }

  Future<void> _replaceContactTags(
    DatabaseExecutor txn,
    Contact contact,
  ) async {
    await txn.delete(
      'contact_tags',
      where: 'contactId = ?',
      whereArgs: [contact.id],
    );

    for (final tag in contact.tags.toSet()) {
      if (tag.isEmpty) continue;
      await txn.insert('contact_tags', {
        'contactId': contact.id,
        'tag': tag,
      });
    }
  }

  Future<void> _replacePrayerRequests(
    DatabaseExecutor txn,
    Contact contact,
  ) async {
    await txn.delete(
      'prayer_requests',
      where: 'contactId = ?',
      whereArgs: [contact.id],
    );

    for (final request in contact.prayerRequests) {
      await txn.insert(
        'prayer_requests',
        request
            .copyWith(contactId: contact.id)
            .toMap(includeId: false),
      );
    }
  }

  /// Retrieve all contacts alongside their related metadata from companion tables.
  Future<List<Contact>> getContacts() async {
    final db = await database;
    final maps = await db.query('contacts');

    final methodRows = await db.query('contact_methods');
    final tagRows = await db.query('contact_tags');
    final contextRows = await db.query('meet_contexts');

    final methodsByContact = <String, List<ContactMethod>>{};
    for (final row in methodRows) {
      final contactId = row['contactId'] as String;
      methodsByContact.putIfAbsent(contactId, () => []);
      methodsByContact[contactId]!.add(
        ContactMethod(
          type: row['type'] as String,
          value: row['value'] as String,
          label: row['label'] as String?,
        ),
      );
    }

    final tagsByContact = <String, List<String>>{};
    for (final row in tagRows) {
      final contactId = row['contactId'] as String;
      tagsByContact.putIfAbsent(contactId, () => []);
      tagsByContact[contactId]!.add(row['tag'] as String);
    }

    final contextsByContact = <String, Map<String, dynamic>>{};
    for (final row in contextRows) {
      final contactId = row['contactId'] as String;
      contextsByContact[contactId] = Map<String, dynamic>.from(row);
    }

    final interactionRows = await db.query(
      'interactions',
      orderBy: 'occurredAt DESC',
    );

    final interactionsByContact = <String, List<Interaction>>{};
    for (final row in interactionRows) {
      final contactId = row['contactId'] as String;
      interactionsByContact.putIfAbsent(contactId, () => []);
      interactionsByContact[contactId]!.add(
        Interaction.fromMap(Map<String, dynamic>.from(row)),
      );
    }

    final prayerRows = await db.query(
      'prayer_requests',
      orderBy: 'requestedAt DESC',
    );

    final prayersByContact = <String, List<PrayerRequest>>{};
    for (final row in prayerRows) {
      final contactId = row['contactId'] as String;
      prayersByContact.putIfAbsent(contactId, () => []);
      prayersByContact[contactId]!.add(
        PrayerRequest.fromMap(Map<String, dynamic>.from(row)),
      );
    }

    return maps.map((map) {
      final contactMap = Map<String, dynamic>.from(map);

      contactMap['interactions'] = interactionsByContact[contactMap['id']]?.map(
                (interaction) => interaction.toMap(),
              ).toList() ??
          [];

      contactMap['contactMethods'] = methodsByContact[contactMap['id']]?.map(
                (method) => method.toMap(),
              ).toList() ??
          [];
      contactMap['tags'] = tagsByContact[contactMap['id']] ?? [];
      final context = contextsByContact[contactMap['id']];
      contactMap['metThroughId'] = context?['metThroughId'];
      contactMap['firstMeetingNotes'] = context?['firstMeetingNotes'];
      contactMap['prayerRequests'] = prayersByContact[contactMap['id']]?.map(
                (request) => request.toMap(),
              ).toList() ??
          [];

      return Contact.fromMap(contactMap);
    }).toList();
  }

  Future<Interaction> insertInteraction(Interaction interaction) async {
    final db = await database;
    final id = await db.insert(
      'interactions',
      interaction.toMap(includeId: false),
    );
    return interaction.copyWith(id: id);
  }

  Future<void> updateInteraction(Interaction interaction) async {
    final db = await database;
    await db.update(
      'interactions',
      interaction.toMap(includeId: false),
      where: 'id = ?',
      whereArgs: [interaction.id],
    );
  }

  Future<void> deleteInteraction(int id) async {
    final db = await database;
    await db.delete(
      'interactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Interaction>> getInteractionsForContact(String contactId) async {
    final db = await database;
    final rows = await db.query(
      'interactions',
      where: 'contactId = ?',
      whereArgs: [contactId],
      orderBy: 'occurredAt DESC',
    );

    return rows
        .map((row) => Interaction.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Delete a contact by [id].
  Future<int> deleteContact(String id) async {
    final db = await database;
    return db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update a [Contact] by [id].
  Future<void> updateContact(Contact contact) async {
    final db = await database;

    await db.transaction((txn) async {
      await _upsertContactRow(txn, contact, isUpdate: true);
    });
  }

  Future<List<String>> getAllTags() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT DISTINCT tag FROM contact_tags');
    return rows
        .map((row) => row['tag'] as String)
        .where((tag) => tag.isNotEmpty)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<Relationship> upsertRelationship(Relationship relationship) async {
    final db = await database;

    if (relationship.id == null) {
      final id = await db.insert(
        'relationships',
        relationship.toMap(includeId: false),
      );
      return relationship.copyWith(id: id);
    } else {
      await db.update(
        'relationships',
        relationship.toMap(includeId: false),
        where: 'id = ?',
        whereArgs: [relationship.id],
      );
      return relationship;
    }
  }

  Future<void> deleteRelationship(int id) async {
    final db = await database;
    await db.delete(
      'relationships',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Relationship>> getRelationshipsForContact(String contactId) async {
    final db = await database;
    final rows = await db.query(
      'relationships',
      where: 'sourceContactId = ? OR targetContactId = ?',
      whereArgs: [contactId, contactId],
    );

    return rows
        .map((row) => Relationship.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<Relationship>> getAllRelationships() async {
    final db = await database;
    final rows = await db.query('relationships');
    return rows
        .map((row) => Relationship.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<PrayerRequest> insertPrayerRequest(PrayerRequest request) async {
    final db = await database;
    final id = await db.insert(
      'prayer_requests',
      request.toMap(includeId: false),
    );
    return request.copyWith(id: id);
  }

  Future<void> updatePrayerRequest(PrayerRequest request) async {
    if (request.id == null) {
      await insertPrayerRequest(request);
      return;
    }

    final db = await database;
    await db.update(
      'prayer_requests',
      request.toMap(includeId: false),
      where: 'id = ?',
      whereArgs: [request.id],
    );
  }

  Future<void> deletePrayerRequest(int id) async {
    final db = await database;
    await db.delete(
      'prayer_requests',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PrayerRequest>> getPrayerRequestsForContact(
    String contactId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'prayer_requests',
      where: 'contactId = ?',
      whereArgs: [contactId],
      orderBy: 'requestedAt DESC',
    );

    return rows
        .map((row) => PrayerRequest.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
  }) async {
    final db = await database;
    final orderBy = latestAnsweredFirst
        ? 'COALESCE(answeredAt, requestedAt) DESC'
        : 'requestedAt DESC';
    final rows = await db.query(
      'prayer_requests',
      where: status != null ? 'status = ?' : null,
      whereArgs: status != null ? [status.name] : null,
      orderBy: orderBy,
      limit: limit,
    );

    return rows
        .map((row) => PrayerRequest.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Map<PrayerRequestStatus, int>> getPrayerRequestCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) as total
      FROM prayer_requests
      GROUP BY status
    ''');

    final counts = {
      for (final status in PrayerRequestStatus.values) status: 0,
    };

    for (final row in rows) {
      final status =
          PrayerRequestStatusX.fromStorage(row['status'] as String?);
      counts[status] = (row['total'] as int?) ?? 0;
    }

    return counts;
  }
}
