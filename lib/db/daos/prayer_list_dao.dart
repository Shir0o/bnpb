import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/prayer_list.dart';
import '../base_dao.dart';

class PrayerListDao extends BaseDao {
  PrayerListDao(super.dbHelper);

  Future<List<PrayerList>> getPrayerLists() async {
    final db = await database;
    await _reconcileDefaultPrayerList(db);
    final listRows = await db.query(
      'prayer_lists',
      where: 'deletedAt IS NULL',
      orderBy: 'displayIndex ASC, name ASC',
    );

    if (listRows.isEmpty) return [];

    final listIds = listRows.map((row) => row['id'] as String).toList();
    final memberRows = await chunkedQuery(
      table: 'prayer_list_members',
      inColumn: 'listId',
      values: listIds,
    );

    final membersByList = <String, List<String>>{};
    for (final row in memberRows) {
      final listId = row['listId'] as String;
      final contactId = row['contactId'] as String;
      membersByList.putIfAbsent(listId, () => []).add(contactId);
    }

    return listRows.map((row) {
      final listId = row['id'] as String;
      return PrayerList.fromMap(row, contactIds: membersByList[listId] ?? []);
    }).toList();
  }

  Future<void> _reconcileDefaultPrayerList(Database db) async {
    final defaultRows = await db.query(
      'prayer_lists',
      where: 'LOWER(TRIM(name)) = ? AND deletedAt IS NULL',
      whereArgs: [PrayerList.defaultListName.toLowerCase()],
      orderBy: 'displayIndex ASC',
    );
    if (defaultRows.isEmpty) return;

    if (defaultRows.length == 1 &&
        defaultRows.first['id'] == PrayerList.defaultListId) {
      return;
    }

    await db.transaction((txn) async {
      final allListIds = defaultRows.map((row) => row['id'] as String).toList();
      final placeholders = List.filled(allListIds.length, '?').join(',');
      final memberRows = await txn.query(
        'prayer_list_members',
        columns: ['contactId'],
        where: 'listId IN ($placeholders)',
        whereArgs: allListIds,
      );
      final consolidatedMemberIds = {
        for (final memberRow in memberRows) memberRow['contactId'] as String,
      };

      final defaultIdMatch = defaultRows
          .where((row) => row['id'] == PrayerList.defaultListId)
          .firstOrNull;
      final primaryRow = defaultIdMatch ?? defaultRows.first;

      for (final listRow in defaultRows) {
        final listId = listRow['id'] as String;
        await txn.delete('prayer_list_members',
            where: 'listId = ?', whereArgs: [listId]);
        await txn.delete('prayer_lists', where: 'id = ?', whereArgs: [listId]);
      }

      final canonicalRow = Map<String, dynamic>.from(primaryRow);
      canonicalRow['id'] = PrayerList.defaultListId;
      await txn.insert('prayer_lists', canonicalRow,
          conflictAlgorithm: ConflictAlgorithm.replace);

      final validContactIds =
          await _existingContactIds(txn, consolidatedMemberIds);
      for (final contactId in validContactIds) {
        await txn.insert(
          'prayer_list_members',
          {
            'listId': PrayerList.defaultListId,
            'contactId': contactId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Ensures the default "My Prayer List" exists and returns it.
  Future<PrayerList> ensureDefaultPrayerList() async {
    final existing = await getPrayerList(PrayerList.defaultListId);
    if (existing != null) return existing;
    final lists = await getPrayerLists();
    final match = lists
        .where((l) =>
            l.name.trim().toLowerCase() ==
            PrayerList.defaultListName.toLowerCase())
        .firstOrNull;
    if (match != null) return match;
    final defaultList = PrayerList.create(
      name: PrayerList.defaultListName,
      description: 'People I am praying for',
    );
    await insertPrayerList(defaultList);
    return defaultList;
  }

  Future<List<PrayerList>> getPrayerListsModifiedSince(DateTime? since) async {
    final db = await database;
    await _reconcileDefaultPrayerList(db);
    String? where;
    List<Object>? whereArgs;

    if (since != null) {
      where = 'updatedAt > ?';
      whereArgs = [since.toIso8601String()];
    }

    final listRows = await db.query(
      'prayer_lists',
      where: where,
      whereArgs: whereArgs,
    );

    if (listRows.isEmpty) return [];

    final listIds = listRows.map((row) => row['id'] as String).toList();
    final memberRows = await chunkedQuery(
      table: 'prayer_list_members',
      inColumn: 'listId',
      values: listIds,
    );

    final membersByList = <String, List<String>>{};
    for (final row in memberRows) {
      final listId = row['listId'] as String;
      final contactId = row['contactId'] as String;
      membersByList.putIfAbsent(listId, () => []).add(contactId);
    }

    return listRows.map((row) {
      final listId = row['id'] as String;
      return PrayerList.fromMap(row, contactIds: membersByList[listId] ?? []);
    }).toList();
  }

  Future<PrayerList?> getPrayerList(String id) async {
    final db = await database;
    final rows = await db.query(
      'prayer_lists',
      where: 'id = ? AND deletedAt IS NULL',
      whereArgs: [id],
    );

    if (rows.isEmpty) return null;

    final memberRows = await db.query(
      'prayer_list_members',
      columns: ['contactId'],
      where: 'listId = ?',
      whereArgs: [id],
    );

    final contactIds = memberRows.map((m) => m['contactId'] as String).toList();

    return PrayerList.fromMap(rows.first, contactIds: contactIds);
  }

  Future<void> insertPrayerList(PrayerList list) async {
    final db = await database;
    final map = list.toMap();
    map['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    map['deletedAt'] = null;

    await db.transaction((txn) async {
      await txn.insert(
        'prayer_lists',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final batch = txn.batch();
      for (final contactId in list.contactIds) {
        batch.insert(
            'prayer_list_members',
            {
              'listId': list.id,
              'contactId': contactId,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updatePrayerList(PrayerList list) async {
    final db = await database;
    final map = list.toMap();
    map['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    map['deletedAt'] = null;

    await db.update('prayer_lists', map, where: 'id = ?', whereArgs: [list.id]);
  }

  Future<void> deletePrayerList(String id) async {
    final db = await database;
    await db.update(
      'prayer_lists',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addContactToPrayerList(String listId, String contactId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
          'prayer_list_members',
          {
            'listId': listId,
            'contactId': contactId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'prayer_lists',
        {'updatedAt': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [listId],
      );
    });
  }

  Future<void> removeContactFromPrayerList(
    String listId,
    String contactId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'prayer_list_members',
        where: 'listId = ? AND contactId = ?',
        whereArgs: [listId, contactId],
      );
      await txn.update(
        'prayer_lists',
        {'updatedAt': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [listId],
      );
    });
  }

  Future<void> upsertPrayerListFromSync(
    DatabaseExecutor db,
    PrayerList list,
  ) async {
    await db.insert(
      'prayer_lists',
      list.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.delete(
      'prayer_list_members',
      where: 'listId = ?',
      whereArgs: [list.id],
    );

    if (list.deletedAt == null) {
      // contactId is a foreign key; skip members that reference a contact
      // that hasn't been imported locally yet instead of letting the whole
      // insert fail (ConflictAlgorithm.ignore does not suppress FK errors).
      final existingContactIds = await _existingContactIds(db, list.contactIds);

      final batch = (db as dynamic).batch() as Batch;
      for (final cid in list.contactIds) {
        if (!existingContactIds.contains(cid)) continue;
        batch.insert(
            'prayer_list_members',
            {
              'listId': list.id,
              'contactId': cid,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<Set<String>> _existingContactIds(
    DatabaseExecutor db,
    Iterable<String> ids,
  ) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet();
    if (unique.isEmpty) return {};

    final existing = <String>{};
    const chunkSize = 900;
    final list = unique.toList();
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
      final chunk = list.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'contacts',
        columns: ['id'],
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
      existing.addAll(rows.map((r) => r['id'] as String));
    }
    return existing;
  }
}
