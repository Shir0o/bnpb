import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../services/security_service.dart';
import '../constants/storage.dart';

// DAOs
import 'daos/contact_dao.dart';
import 'daos/interaction_dao.dart';
import 'daos/prayer_request_dao.dart';
import 'daos/relationship_dao.dart';
import 'daos/prayer_list_dao.dart';

// Models
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/notification_preference.dart';
import '../models/prayer_request.dart';
import '../models/prayer_list.dart';
import '../models/relationship.dart';

class DBHelper {
  static const _dbVersion = 19;

  static final DBHelper _instance = DBHelper._();
  static Database? _database;

  DBHelper._();

  factory DBHelper() => _instance;

  // DAO Instances
  late final ContactDao contactDao = ContactDao(this);
  late final InteractionDao interactionDao = InteractionDao(this);
  late final PrayerRequestDao prayerRequestDao = PrayerRequestDao(this);
  late final RelationshipDao relationshipDao = RelationshipDao(this);
  late final PrayerListDao prayerListDao = PrayerListDao(this);

  @visibleForTesting
  static void setDatabaseForTest(Database db) {
    _database = db;
  }

  @visibleForTesting
  Future<void> createSchemaForTest(Database db) => _createSchema(db);

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Closes the cached database instance and clears the static reference.
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final encryptionKey = await SecurityService().obtainDatabaseKey();
    return openDatabase(
      join(dbPath, StorageConstants.databaseFileName),
      version: _dbVersion,
      password: encryptionKey,
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
        email TEXT,
        phone TEXT,
        notes TEXT,
        updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
        deletedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE meet_contexts (
        contactId TEXT PRIMARY KEY,
        firstMeetingNotes TEXT,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

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
      CREATE TABLE interaction_participants (
        interactionId INTEGER NOT NULL,
        contactId TEXT NOT NULL,
        PRIMARY KEY(interactionId, contactId),
        FOREIGN KEY(interactionId) REFERENCES interactions(id) ON DELETE CASCADE,
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
        deletedAt TEXT,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE,
        FOREIGN KEY(interactionId) REFERENCES interactions(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notification_preferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scopeType TEXT NOT NULL,
        scopeId TEXT NOT NULL,
        channel TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        leadTimeMinutes INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
        CREATE UNIQUE INDEX idx_notification_preferences_scope
      ON notification_preferences(scopeType, scopeId, channel)
    ''');

    await db.execute('''
      CREATE TABLE prayer_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        color TEXT,
        displayIndex INTEGER NOT NULL DEFAULT 0, updatedAt TEXT NOT NULL DEFAULT (datetime('now')), deletedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE prayer_list_members (
        listId TEXT NOT NULL,
        contactId TEXT NOT NULL,
        PRIMARY KEY(listId, contactId),
        FOREIGN KEY(listId) REFERENCES prayer_lists(id) ON DELETE CASCADE,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE prayer_request_participants (
        prayerRequestId INTEGER NOT NULL,
        contactId TEXT NOT NULL,
        PRIMARY KEY(prayerRequestId, contactId),
        FOREIGN KEY(prayerRequestId) REFERENCES prayer_requests(id) ON DELETE CASCADE,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE contacts ADD COLUMN nickname TEXT');
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
          firstMeetingNotes TEXT,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
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
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();
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
          final occurredAt = entryMap['date'] as String? ?? now;

          batch.insert('interactions', {
            'contactId': contactId,
            'occurredAt': occurredAt,
            'summary': summary,
            'medium': 'unspecified',
            'attachments': jsonEncode([]),
          });
        }
      }
      await batch.commit(noResult: true);

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

    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE interactions ADD COLUMN durationMinutes INTEGER',
      );
      await db.execute('ALTER TABLE interactions ADD COLUMN category TEXT');
    }

    if (oldVersion < 7) {
      await db.execute(
        "ALTER TABLE contacts ADD COLUMN keywords TEXT DEFAULT '[]'",
      );
      await db.execute(
        "ALTER TABLE contacts ADD COLUMN photoCues TEXT DEFAULT '[]'",
      );
      await db.execute(
        "ALTER TABLE contacts ADD COLUMN reminderCues TEXT DEFAULT '[]'",
      );
    }

    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notification_preferences (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scopeType TEXT NOT NULL,
          scopeId TEXT NOT NULL,
          channel TEXT NOT NULL,
          enabled INTEGER NOT NULL,
          leadTimeMinutes INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_preferences_scope
        ON notification_preferences(scopeType, scopeId, channel)
      ''');
    }

    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS meet_contexts_new (
          contactId TEXT PRIMARY KEY,
          firstMeetingNotes TEXT,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        INSERT INTO meet_contexts_new (contactId, firstMeetingNotes)
        SELECT contactId, firstMeetingNotes FROM meet_contexts
      ''');

      await db.execute('DROP TABLE IF EXISTS meet_contexts');
      await db.execute('ALTER TABLE meet_contexts_new RENAME TO meet_contexts');
    }

    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS attendance_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          sessionDate TEXT NOT NULL,
          location TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS attendance_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sessionId INTEGER NOT NULL,
          contactId TEXT NOT NULL,
          status TEXT NOT NULL,
          FOREIGN KEY(sessionId) REFERENCES attendance_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE,
        UNIQUE(sessionId, contactId)
      )
    ''');
    }

    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS interactions_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          occurredAt TEXT NOT NULL,
          summary TEXT NOT NULL,
          medium TEXT NOT NULL,
          location TEXT,
          attachments TEXT,
          markForPrayer INTEGER NOT NULL DEFAULT 0,
          followUpAt TEXT,
          durationMinutes INTEGER,
          category TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS interaction_participants (
          interactionId INTEGER NOT NULL,
          contactId TEXT NOT NULL,
          PRIMARY KEY(interactionId, contactId),
          FOREIGN KEY(interactionId) REFERENCES interactions_new(id) ON DELETE CASCADE,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        INSERT INTO interactions_new (
          id, occurredAt, summary, medium, location, attachments,
          markForPrayer, followUpAt, durationMinutes, category
        )
        SELECT
          id, occurredAt, summary, medium, location, attachments,
          markForPrayer, followUpAt, durationMinutes, category
        FROM interactions
      ''');

      await db.execute('''
        INSERT OR IGNORE INTO interaction_participants (interactionId, contactId)
        SELECT id, contactId FROM interactions
      ''');

      await db.execute('DROP TABLE IF EXISTS interactions');
      await db.execute('ALTER TABLE interactions_new RENAME TO interactions');
    }

    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS prayer_lists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          color TEXT,
          displayIndex INTEGER NOT NULL DEFAULT 0, updatedAt TEXT NOT NULL DEFAULT (datetime('now')), deletedAt TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS prayer_list_members (
          listId TEXT NOT NULL,
          contactId TEXT NOT NULL,
          PRIMARY KEY(listId, contactId),
          FOREIGN KEY(listId) REFERENCES prayer_lists(id) ON DELETE CASCADE,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 13) {
      await db.execute('ALTER TABLE contacts ADD COLUMN notes TEXT');
    }

    if (oldVersion < 14) {
      await db.execute(
        "ALTER TABLE contacts ADD COLUMN updatedAt TEXT NOT NULL DEFAULT '1970-01-01T00:00:00.000Z'",
      );
      await db.execute("ALTER TABLE contacts ADD COLUMN deletedAt TEXT");

      await db.execute(
        "ALTER TABLE interactions ADD COLUMN syncId TEXT",
      );
      await db.execute(
        "ALTER TABLE interactions ADD COLUMN updatedAt TEXT NOT NULL DEFAULT '1970-01-01T00:00:00.000Z'",
      );
      await db.execute("ALTER TABLE interactions ADD COLUMN deletedAt TEXT");

      await db.execute(
        "UPDATE interactions SET syncId = lower(hex(randomblob(16))) WHERE syncId IS NULL",
      );

      await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_interactions_syncId ON interactions(syncId)",
      );

      await db.execute("ALTER TABLE prayer_requests ADD COLUMN syncId TEXT");
      await db.execute(
        "ALTER TABLE prayer_requests ADD COLUMN updatedAt TEXT NOT NULL DEFAULT '1970-01-01T00:00:00.000Z'",
      );
      await db.execute("ALTER TABLE prayer_requests ADD COLUMN deletedAt TEXT");

      await db.execute(
        "UPDATE prayer_requests SET syncId = lower(hex(randomblob(16))) WHERE syncId IS NULL",
      );
      await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_prayer_requests_syncId ON prayer_requests(syncId)",
      );
    }

    if (oldVersion < 15) {
      await db.execute('ALTER TABLE contacts ADD COLUMN email TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN phone TEXT');
    }
    if (oldVersion < 16) {
      await db.execute(
        "ALTER TABLE prayer_lists ADD COLUMN updatedAt TEXT NOT NULL DEFAULT '1970-01-01T00:00:00.000Z'",
      );
      await db.execute('ALTER TABLE prayer_lists ADD COLUMN deletedAt TEXT');
    }
    if (oldVersion < 17) {
      final columns = await db.rawQuery('PRAGMA table_info(interactions)');
      final hasCategory = columns.any((column) => column['name'] == 'category');
      final hasNotes = columns.any((column) => column['name'] == 'notes');

      if (hasCategory && !hasNotes) {
        await db.execute(
          'ALTER TABLE interactions RENAME COLUMN category TO notes',
        );
      }
    }
    if (oldVersion < 18) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS prayer_request_participants (
          prayerRequestId INTEGER NOT NULL,
          contactId TEXT NOT NULL,
          PRIMARY KEY(prayerRequestId, contactId),
          FOREIGN KEY(prayerRequestId) REFERENCES prayer_requests(id) ON DELETE CASCADE,
          FOREIGN KEY(contactId) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        INSERT OR IGNORE INTO prayer_request_participants (prayerRequestId, contactId)
        SELECT id, contactId FROM prayer_requests
      ''');
    }
    if (oldVersion < 19) {
      await db.execute('DROP TABLE IF EXISTS contact_tags');
      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final names = columns.map((c) => c['name'] as String).toSet();
      for (final col in ['keywords', 'photoCues', 'reminderCues']) {
        if (names.contains(col)) {
          await db.execute('ALTER TABLE contacts DROP COLUMN $col');
        }
      }
    }
  }

  Future<Map<String, dynamic>> getGlobalMetadata() async {
    final db = await database;
    final contactCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM contacts WHERE deletedAt IS NULL')) ??
        0;
    final interactionCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM interactions WHERE deletedAt IS NULL')) ??
        0;
    final prayerCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM prayer_requests WHERE deletedAt IS NULL')) ??
        0;

    final lastUpdateRow = await db.rawQuery('''
      SELECT MAX(updatedAt) as maxUpdate FROM (
        SELECT updatedAt FROM contacts WHERE deletedAt IS NULL
        UNION ALL
        SELECT updatedAt FROM interactions WHERE deletedAt IS NULL
        UNION ALL
        SELECT updatedAt FROM prayer_requests WHERE deletedAt IS NULL
      )
    ''');
    final lastUpdate = lastUpdateRow.first['maxUpdate'] as String?;

    return {
      'contactCount': contactCount,
      'interactionCount': interactionCount,
      'prayerCount': prayerCount,
      'lastUpdate': lastUpdate,
    };
  }

  // --- Maintenance Methods ---

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('meet_contexts');
      await txn.delete('interaction_participants');
      await txn.delete('interactions');
      await txn.delete('relationships');
      await txn.delete('prayer_request_participants');
      await txn.delete('prayer_requests');
      await txn.delete('prayer_list_members');
      await txn.delete('prayer_lists');
      await txn.delete('notification_preferences');
      await txn.delete('contacts');
    });
  }

  // --- Notification Preference Methods (Kept in DBHelper for now as they are simple) ---

  Future<NotificationPreference?> getNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    final db = await database;
    final rows = await db.query(
      'notification_preferences',
      where: 'scopeType = ? AND scopeId = ? AND channel = ?',
      whereArgs: [scopeType.name, scopeId, channel.name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotificationPreference.fromMap(
        Map<String, dynamic>.from(rows.first));
  }

  Future<List<NotificationPreference>> getNotificationPreferences({
    NotificationScopeType? scopeType,
  }) async {
    final db = await database;
    final rows = await db.query(
      'notification_preferences',
      where: scopeType != null ? 'scopeType = ?' : null,
      whereArgs: scopeType != null ? [scopeType.name] : null,
    );
    return rows
        .map((row) =>
            NotificationPreference.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<NotificationPreference> upsertNotificationPreference(
      NotificationPreference preference) async {
    final db = await database;
    final id = await db.insert(
      'notification_preferences',
      preference.toMap(includeId: false),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return preference.copyWith(id: id);
  }

  Future<void> deleteNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    final db = await database;
    await db.delete(
      'notification_preferences',
      where: 'scopeType = ? AND scopeId = ? AND channel = ?',
      whereArgs: [scopeType.name, scopeId, channel.name],
    );
  }

  // --- Bridge Methods ---

  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) =>
      contactDao.getContacts(
        contactId: contactId,
        contactIds: contactIds,
        updatedSince: updatedSince,
        includeDeleted: includeDeleted,
      );

  Future<List<Contact>> getContactsModifiedSince(DateTime? since) =>
      contactDao.getContacts(updatedSince: since, includeDeleted: true);

  Future<Contact?> getContactById(String id) => contactDao.getContactById(id);
  Future<void> insertContact(Contact contact) =>
      contactDao.insertContact(contact);
  Future<void> updateContact(Contact contact) =>
      contactDao.updateContact(contact);
  Future<int> deleteContact(String id) => contactDao.deleteContact(id);
  Future<List<String>> getDistinctLocations() =>
      contactDao.getDistinctLocations();

  Future<Interaction> insertInteraction(Interaction interaction) =>
      interactionDao.insertInteraction(interaction);
  Future<void> updateInteraction(Interaction interaction) =>
      interactionDao.updateInteraction(interaction);
  Future<void> deleteInteraction(int id) =>
      interactionDao.deleteInteraction(id);
  Future<List<Interaction>> getInteractions({
    DateTime? start,
    DateTime? end,
    String? contactId,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) =>
      interactionDao.getInteractions(
        start: start,
        end: end,
        contactId: contactId,
        updatedSince: updatedSince,
        includeDeleted: includeDeleted,
      );
  Future<List<Interaction>> getPrayerFocusInteractions({int limit = 10}) async {
    final db = await database;
    final rows = await db.query(
      'interactions',
      where: 'markForPrayer = ? AND deletedAt IS NULL',
      whereArgs: const [1],
      orderBy: 'occurredAt DESC',
      limit: limit,
    );

    if (rows.isEmpty) return [];

    final interactionIds = rows.map((row) => row['id'] as int).toSet();
    final participantsByInteraction =
        await interactionDao.getParticipantsForInteractions(
      interactionIds,
    );

    return rows.map((row) {
      final interactionMap = Map<String, dynamic>.from(row);
      interactionMap['participantIds'] =
          participantsByInteraction[row['id'] as int] ?? const <String>[];
      return Interaction.fromMap(interactionMap);
    }).toList();
  }

  Future<List<Interaction>> getInteractionsForContact(String contactId) =>
      interactionDao.getInteractions(contactId: contactId);

  Future<List<Interaction>> getInteractionsModifiedSince(DateTime? since) =>
      interactionDao.getInteractions(updatedSince: since, includeDeleted: true);
  Future<Interaction?> getInteractionById(int id) =>
      interactionDao.getInteractionById(id);

  @visibleForTesting
  Future<void> upsertContactRowForTest(
    DatabaseExecutor txn,
    Contact contact, {
    required bool isUpdate,
  }) async {
    await contactDao.upsertContactRow(txn, contact,
        isUpdate: isUpdate, syncNested: true);
  }

  Future<bool> interactionExists({
    required String contactId,
    required DateTime occurredAt,
    required String summary,
  }) =>
      interactionDao.interactionExists(
        contactId: contactId,
        occurredAt: occurredAt,
        summary: summary,
      );

  Future<List<PrayerRequest>> getPrayerRequestsForContact(String contactId) =>
      prayerRequestDao.getPrayerRequestsForContacts([contactId]).then(
          (map) => map[contactId] ?? []);

  Future<PrayerRequest> insertPrayerRequest(PrayerRequest request) =>
      prayerRequestDao.insertPrayerRequest(request);
  Future<void> updatePrayerRequest(PrayerRequest request) =>
      prayerRequestDao.updatePrayerRequest(request);
  Future<void> deletePrayerRequest(int id) =>
      prayerRequestDao.deletePrayerRequest(id);
  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) =>
      prayerRequestDao.getPrayerRequests(
        status: status,
        limit: limit,
        latestAnsweredFirst: latestAnsweredFirst,
        updatedSince: updatedSince,
        includeDeleted: includeDeleted,
      );
  Future<List<PrayerRequest>> getPrayerRequestsModifiedSince(DateTime? since) =>
      prayerRequestDao.getPrayerRequests(
          updatedSince: since, includeDeleted: true);
  Future<Map<PrayerRequestStatus, int>> getPrayerRequestCounts() =>
      prayerRequestDao.getPrayerRequestCounts();
  Future<List<String>> getPrayerCategories() =>
      prayerRequestDao.getPrayerCategories();

  Future<Relationship> upsertRelationship(Relationship relationship) =>
      relationshipDao.upsertRelationship(relationship);
  Future<void> deleteRelationship(int id) =>
      relationshipDao.deleteRelationship(id);
  Future<List<Relationship>> getRelationshipsForContact(String contactId) =>
      relationshipDao.getRelationshipsForContact(contactId);
  Future<List<Relationship>> getAllRelationships() =>
      relationshipDao.getAllRelationships();

  Future<List<PrayerList>> getPrayerLists() => prayerListDao.getPrayerLists();
  Future<List<PrayerList>> getPrayerListsModifiedSince(DateTime? since) =>
      prayerListDao.getPrayerListsModifiedSince(since);
  Future<PrayerList?> getPrayerList(String id) =>
      prayerListDao.getPrayerList(id);
  Future<void> insertPrayerList(PrayerList list) =>
      prayerListDao.insertPrayerList(list);
  Future<void> updatePrayerList(PrayerList list) =>
      prayerListDao.updatePrayerList(list);
  Future<void> deletePrayerList(String id) =>
      prayerListDao.deletePrayerList(id);
  Future<void> addContactToPrayerList(String listId, String contactId) =>
      prayerListDao.addContactToPrayerList(listId, contactId);
  Future<void> removeContactFromPrayerList(String listId, String contactId) =>
      prayerListDao.removeContactFromPrayerList(listId, contactId);

  Future<void> replaceInteractionParticipants(
          DatabaseExecutor db, int id, List<String> participants) =>
      interactionDao.replaceInteractionParticipants(db, id, participants);

  Future<void> replacePrayerRequestParticipants(
          DatabaseExecutor db, int id, List<String> participants) =>
      prayerRequestDao.replacePrayerRequestParticipants(db, id, participants);

  Future<void> upsertPrayerListFromSync(DatabaseExecutor db, PrayerList list) =>
      prayerListDao.upsertPrayerListFromSync(db, list);

  // Special bridge for SyncCoordinator
  Future<void> upsertContactFromSync(DatabaseExecutor txn, Contact contact,
          {required bool isUpdate}) =>
      contactDao.upsertContactRow(txn, contact,
          isUpdate: isUpdate, syncNested: false, forceNowTimestamps: false);
}
