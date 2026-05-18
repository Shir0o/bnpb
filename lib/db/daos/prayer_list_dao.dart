import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/prayer_list.dart';
import '../base_dao.dart';

class PrayerListDao extends BaseDao {
  PrayerListDao(super.dbHelper);

  Future<List<PrayerList>> getPrayerLists() async {
    final db = await database;
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

  Future<List<PrayerList>> getPrayerListsModifiedSince(DateTime? since) async {
    final db = await database;
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
    await addContactsToPrayerList(listId, [contactId]);
  }

  Future<void> addContactsToPrayerList(
    String listId,
    List<String> contactIds,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final contactId in contactIds) {
        batch.insert(
            'prayer_list_members',
            {
              'listId': listId,
              'contactId': contactId,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
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
      final batch = (db as dynamic).batch() as Batch;
      for (final cid in list.contactIds) {
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
}
