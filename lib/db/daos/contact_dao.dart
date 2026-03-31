import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/contact.dart';
import '../base_dao.dart';

class ContactDao extends BaseDao {
  ContactDao(super.dbHelper);

  /// Insert or replace a [Contact] in the database.
  Future<void> insertContact(Contact contact) async {
    final db = await database;
    await db.transaction((txn) async {
      await upsertContactRow(txn, contact, isUpdate: false);
    });
  }

  /// Update a [Contact] in the database.
  Future<void> updateContact(Contact contact) async {
    final db = await database;
    await db.transaction((txn) async {
      await upsertContactRow(txn, contact, isUpdate: true);
    });
  }

  Future<void> upsertContactRow(
    DatabaseExecutor txn,
    Contact contact, {
    required bool isUpdate,
    bool syncNested = true,
    bool forceNowTimestamps = true,
  }) async {
    final baseMap = <String, dynamic>{
      'id': contact.id,
      'firstName': contact.firstName,
      'middleName': contact.middleName,
      'lastName': contact.lastName,
      'nickname': contact.nickname,
      'location': contact.location,
      'email': contact.email,
      'phone': contact.phone,
      'keywords': jsonEncode(contact.recognitionKeywords),
      'photoCues': jsonEncode(contact.recognitionPhotoUris),
      'reminderCues': jsonEncode(contact.recognitionReminders),
      'notes': contact.notes,
      'updatedAt': forceNowTimestamps
          ? DateTime.now().toUtc().toIso8601String()
          : contact.updatedAt.toIso8601String(),
      'deletedAt':
          forceNowTimestamps ? null : contact.deletedAt?.toIso8601String(),
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
    await _replaceContactTags(txn, contact);

    if (syncNested) {
      // NOTE: These call out to other DAOs ideally, but for now we'll use DBHelper instances or internal methods
      // To avoid circular dependencies, we might need to keep some logic in DBHelper or pass DAOs.
      await dbHelper.interactionDao.replaceInteractionsForContact(txn, contact);

      if (contact.prayerRequests.isNotEmpty) {
        await dbHelper.prayerRequestDao
            .replacePrayerRequestsForContact(txn, contact);
      }
    }
  }

  Future<void> _upsertMeetContext(DatabaseExecutor txn, Contact contact) async {
    final hasContext = contact.firstMeetingNotes != null &&
        contact.firstMeetingNotes!.isNotEmpty;

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
          'firstMeetingNotes': contact.firstMeetingNotes,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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

    final batch = txn.batch();
    for (final tag in contact.tags.toSet()) {
      if (tag.isEmpty) continue;
      batch.insert('contact_tags', {'contactId': contact.id, 'tag': tag});
    }
    await batch.commit(noResult: true);
  }

  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    final db = await database;

    if (contactIds != null && contactIds.isEmpty && contactId == null) {
      return [];
    }

    String where = includeDeleted ? '1 = 1' : 'deletedAt IS NULL';
    List<Object?> whereArgs = [];

    if (contactId != null) {
      where += ' AND id = ?';
      whereArgs.add(contactId);
    }

    if (contactIds != null && contactIds.isNotEmpty) {
      final placeholders = List.filled(contactIds.length, '?').join(',');
      where += ' AND id IN ($placeholders)';
      whereArgs.addAll(contactIds);
    }

    if (updatedSince != null) {
      where += ' AND updatedAt > ?';
      whereArgs.add(updatedSince.toIso8601String());
    }

    final contactRows = await db.query(
      'contacts',
      where: where,
      whereArgs: whereArgs,
    );

    if (contactRows.isEmpty) return [];

    final retrievedContactIds =
        contactRows.map((c) => c['id'] as String).toList();
    final retrievedContactIdsSet = retrievedContactIds.toSet();

    final isFetchAllActive = contactId == null &&
        (contactIds == null || contactIds.isEmpty) &&
        updatedSince == null &&
        !includeDeleted;

    // Fetch Tags
    final List<Map<String, Object?>> tagRows;
    if (isFetchAllActive) {
      tagRows = await db.rawQuery('''
        SELECT t.* FROM contact_tags t
        JOIN contacts c ON t.contactId = c.id
        WHERE c.deletedAt IS NULL
      ''');
    } else {
      tagRows = await chunkedQuery(
        table: 'contact_tags',
        inColumn: 'contactId',
        values: retrievedContactIds,
      );
    }

    final tagsByContact = <String, List<String>>{};
    for (final row in tagRows) {
      final cId = row['contactId'] as String;
      final tag = row['tag'] as String;
      tagsByContact.putIfAbsent(cId, () => []).add(tag);
    }

    // Fetch Interactions
    final interactionsByContact =
        await dbHelper.interactionDao.getInteractionsForContacts(
      retrievedContactIds,
      isFetchAllActive: isFetchAllActive,
    );

    // Fetch Prayer Requests
    final requestsByContact =
        await dbHelper.prayerRequestDao.getPrayerRequestsForContacts(
      retrievedContactIds,
      isFetchAllActive: isFetchAllActive,
    );

    // Fetch Relationships
    final relationshipsByContact =
        await dbHelper.relationshipDao.getRelationshipsForContacts(
      retrievedContactIds,
      retrievedContactIdsSet,
      isFetchAllActive: isFetchAllActive,
    );

    // Fetch Meet Contexts
    final List<Map<String, Object?>> contextRows;
    if (isFetchAllActive) {
      contextRows = await db.rawQuery('''
        SELECT mc.* FROM meet_contexts mc
        JOIN contacts c ON mc.contactId = c.id
        WHERE c.deletedAt IS NULL
      ''');
    } else {
      contextRows = await chunkedQuery(
        table: 'meet_contexts',
        inColumn: 'contactId',
        values: retrievedContactIds,
      );
    }
    final contextMap = {
      for (var r in contextRows)
        r['contactId'] as String: r['firstMeetingNotes'] as String,
    };

    return contactRows.map((row) {
      final cId = row['id'] as String;
      final contactMap = Map<String, dynamic>.from(row);
      contactMap['tags'] = tagsByContact[cId] ?? [];
      contactMap['interactions'] =
          (interactionsByContact[cId] ?? []).map((i) => i.toMap()).toList();
      contactMap['prayerRequests'] =
          (requestsByContact[cId] ?? []).map((r) => r.toMap()).toList();
      contactMap['relationships'] =
          (relationshipsByContact[cId] ?? []).map((r) => r.toMap()).toList();
      contactMap['firstMeetingNotes'] = contextMap[cId];

      if (contactMap['keywords'] != null) {
        contactMap['recognitionKeywords'] =
            _parseStringList(contactMap['keywords']);
        contactMap.remove('keywords');
      }
      if (contactMap['photoCues'] != null) {
        contactMap['recognitionPhotoUris'] =
            _parseStringList(contactMap['photoCues']);
        contactMap.remove('photoCues');
      }
      if (contactMap['reminderCues'] != null) {
        contactMap['recognitionReminders'] =
            _parseStringList(contactMap['reminderCues']);
        contactMap.remove('reminderCues');
      }

      return Contact.fromMap(contactMap);
    }).toList();
  }

  Future<Contact?> getContactById(String id) async {
    final contacts = await getContacts(contactId: id);
    return contacts.isNotEmpty ? contacts.first : null;
  }

  Future<int> deleteContact(String id) async {
    final db = await database;
    return db.update(
      'contacts',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getAllTags() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT t.tag
      FROM contact_tags t
      JOIN contacts c ON c.id = t.contactId
      WHERE c.deletedAt IS NULL
    ''');

    return rows
        .map((row) => row['tag'] as String)
        .where((tag) => tag.isNotEmpty)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      if (value.isEmpty) return const [];
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((entry) => entry.toString()).toList();
        }
      } catch (_) {
        return value
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
      }
    }
    if (value is List) {
      return value.map((entry) => entry.toString()).toList();
    }
    return const [];
  }
}
