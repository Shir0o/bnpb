import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/contact.dart';

class DBHelper {
  static const _dbName = 'contacts.db';
  static const _dbVersion = 2;

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
        location TEXT,
        history TEXT
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
  }

  // -------------------------------------------------------------
  // CONTACTS METHODS
  // -------------------------------------------------------------

  /// Insert or replace a [Contact] in the database.
  /// The `history` list is converted to JSON before insertion.
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
    final contactMap = contact.toMap();
    final historyJson = jsonEncode(contactMap['history']);

    final baseMap = <String, dynamic>{
      'id': contact.id,
      'firstName': contact.firstName,
      'middleName': contact.middleName,
      'lastName': contact.lastName,
      'nickname': contact.nickname,
      'location': contact.location,
      'history': historyJson,
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

  /// Retrieve all contacts and decode the `history` JSON back into a List of Maps.
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

    return maps.map((map) {
      final contactMap = Map<String, dynamic>.from(map);
      final historyJson = contactMap['history'] as String?;
      if (historyJson != null && historyJson.isNotEmpty) {
        contactMap['history'] = jsonDecode(historyJson);
      } else {
        contactMap['history'] = [];
      }

      contactMap['contactMethods'] = methodsByContact[contactMap['id']]?.map(
                (method) => method.toMap(),
              ).toList() ??
          [];
      contactMap['tags'] = tagsByContact[contactMap['id']] ?? [];
      final context = contextsByContact[contactMap['id']];
      contactMap['metThroughId'] = context?['metThroughId'];
      contactMap['firstMeetingNotes'] = context?['firstMeetingNotes'];

      return Contact.fromMap(contactMap);
    }).toList();
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
}