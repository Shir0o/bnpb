import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/contact.dart';
import '../../models/prayer_request.dart';
import '../base_dao.dart';

class PrayerRequestDao extends BaseDao {
  PrayerRequestDao(super.dbHelper);

  Future<PrayerRequest> insertPrayerRequest(PrayerRequest request) async {
    final db = await database;
    final reqMap = request.toMap(includeId: false);
    reqMap.remove('participantIds');
    reqMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    reqMap['deletedAt'] = null;

    int id = -1;
    await db.transaction((txn) async {
      id = await txn.insert('prayer_requests', reqMap);
      await replacePrayerRequestParticipants(txn, id, request.participantIds);
    });

    return request.copyWith(id: id);
  }

  Future<void> updatePrayerRequest(PrayerRequest request) async {
    if (request.id == null) {
      await insertPrayerRequest(request);
      return;
    }

    final db = await database;
    final reqMap = request.toMap(includeId: false);
    reqMap.remove('participantIds');
    reqMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    reqMap['deletedAt'] = null;

    await db.transaction((txn) async {
      await txn.update(
        'prayer_requests',
        reqMap,
        where: 'id = ?',
        whereArgs: [request.id],
      );
      await replacePrayerRequestParticipants(
        txn,
        request.id!,
        request.participantIds,
      );
    });
  }

  Future<void> deletePrayerRequest(int id) async {
    final db = await database;
    await db.update(
      'prayer_requests',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replacePrayerRequestParticipants(
    DatabaseExecutor txn,
    int requestId,
    List<String> participants,
  ) async {
    await txn.delete(
      'prayer_request_participants',
      where: 'prayerRequestId = ?',
      whereArgs: [requestId],
    );

    final batch = txn.batch();
    for (final contactId in participants) {
      batch.insert('prayer_request_participants', {
        'prayerRequestId': requestId,
        'contactId': contactId,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> replacePrayerRequestsForContact(
    DatabaseExecutor txn,
    Contact contact,
  ) async {
    final existingRows = await txn.query(
      'prayer_request_participants',
      columns: ['prayerRequestId'],
      where: 'contactId = ?',
      whereArgs: [contact.id],
    );
    final existingIds =
        existingRows.map((r) => r['prayerRequestId'] as int).toSet();
    final newIds =
        contact.prayerRequests.map((r) => r.id).whereType<int>().toSet();

    final now = DateTime.now().toUtc().toIso8601String();
    final idsToDelete = existingIds.difference(newIds);
    if (idsToDelete.isNotEmpty) {
      final batch = txn.batch();
      for (final id in idsToDelete) {
        batch.update(
          'prayer_requests',
          {'deletedAt': now, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
    }

    if (contact.prayerRequests.isEmpty) return;

    final upsertBatch = txn.batch();
    for (final request in contact.prayerRequests) {
      final reqMap = request.toMap(includeId: true);
      reqMap.remove('participantIds');
      reqMap['updatedAt'] = now;
      upsertBatch.insert(
        'prayer_requests',
        reqMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final results = await upsertBatch.commit(noResult: false);

    final participantBatch = txn.batch();
    for (int i = 0; i < contact.prayerRequests.length; i++) {
      final request = contact.prayerRequests[i];
      final requestId = results[i] as int;
      final participants = {...request.participantIds, contact.id}.toList();

      participantBatch.delete(
        'prayer_request_participants',
        where: 'prayerRequestId = ?',
        whereArgs: [requestId],
      );

      for (final contactId in participants) {
        participantBatch.insert('prayer_request_participants', {
          'prayerRequestId': requestId,
          'contactId': contactId,
        });
      }
    }
    await participantBatch.commit(noResult: true);
  }

  Future<Map<String, List<PrayerRequest>>> getPrayerRequestsForContacts(
    List<String> contactIds, {
    bool isFetchAllActive = false,
  }) async {
    final db = await database;
    final List<Map<String, Object?>> prayerParticipantRows;

    if (isFetchAllActive) {
      prayerParticipantRows = await db.rawQuery('''
        SELECT prp.contactId, pr.*
        FROM prayer_request_participants prp
        JOIN prayer_requests pr ON prp.prayerRequestId = pr.id
        JOIN contacts c ON prp.contactId = c.id
        WHERE c.deletedAt IS NULL AND pr.deletedAt IS NULL
      ''');
    } else {
      prayerParticipantRows = [];
      const int batchSize = 900;
      for (var i = 0; i < contactIds.length; i += batchSize) {
        final end = (i + batchSize < contactIds.length)
            ? i + batchSize
            : contactIds.length;
        final chunk = contactIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');

        final rows = await db.rawQuery('''
          SELECT prp.contactId, pr.*
          FROM prayer_request_participants prp
          JOIN prayer_requests pr ON prp.prayerRequestId = pr.id
          WHERE prp.contactId IN ($placeholders) AND pr.deletedAt IS NULL
        ''', chunk);
        prayerParticipantRows.addAll(rows);
      }
    }

    final fetchedPrayerIds =
        prayerParticipantRows.map((r) => r['id'] as int).toSet();
    final allPrayerParticipantsMap = await getParticipantsForPrayerRequests(
      fetchedPrayerIds,
    );

    final requestsByContact = <String, List<PrayerRequest>>{};
    for (final row in prayerParticipantRows) {
      final cId = row['contactId'] as String;
      final prId = row['id'] as int;
      final prMap = Map<String, dynamic>.from(row);
      prMap.remove('contactId');
      prMap['participantIds'] = allPrayerParticipantsMap[prId] ?? [];

      requestsByContact
          .putIfAbsent(cId, () => [])
          .add(PrayerRequest.fromMap(prMap));
    }

    return requestsByContact;
  }

  Future<Map<int, List<String>>> getParticipantsForPrayerRequests(
    Iterable<int> prayerRequestIds,
  ) async {
    if (prayerRequestIds.isEmpty) return {};
    final rows = await chunkedQuery(
      table: 'prayer_request_participants',
      inColumn: 'prayerRequestId',
      values: prayerRequestIds.toList(),
    );

    final participantsByRequest = <int, List<String>>{};
    for (final row in rows) {
      final requestId = row['prayerRequestId'] as int;
      final participantId = row['contactId'] as String;
      participantsByRequest.putIfAbsent(requestId, () => []);
      participantsByRequest[requestId]!.add(participantId);
    }

    return participantsByRequest;
  }

  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final orderBy = latestAnsweredFirst
        ? "CASE WHEN status = 'pending' THEN 0 ELSE 1 END, COALESCE(answeredAt, requestedAt) DESC"
        : "CASE WHEN status = 'pending' THEN 0 ELSE 1 END, requestedAt DESC";

    String where = includeDeleted ? '1 = 1' : 'deletedAt IS NULL';
    List<Object> whereArgs = [];

    if (status != null) {
      where += ' AND status = ?';
      whereArgs.add(status.name);
    }

    if (updatedSince != null) {
      where += ' AND updatedAt > ?';
      whereArgs.add(updatedSince.toIso8601String());
    }

    final rows = await db.query(
      'prayer_requests',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );

    final requests = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    final ids = requests.map((r) => r['id'] as int).toList();
    final participantsMap = await getParticipantsForPrayerRequests(ids);

    return requests.map((r) {
      final id = r['id'] as int;
      r['participantIds'] = participantsMap[id] ?? [];
      return PrayerRequest.fromMap(r);
    }).toList();
  }

  Future<Map<PrayerRequestStatus, int>> getPrayerRequestCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) as total
      FROM prayer_requests
      WHERE deletedAt IS NULL
      GROUP BY status
    ''');

    final counts = {for (final status in PrayerRequestStatus.values) status: 0};

    for (final row in rows) {
      final status = PrayerRequestStatusX.fromStorage(row['status'] as String?);
      counts[status] = (row['total'] as int?) ?? 0;
    }

    return counts;
  }

  Future<List<String>> getPrayerCategories() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT TRIM(category) as category
      FROM prayer_requests
      WHERE category IS NOT NULL AND TRIM(category) != '' AND deletedAt IS NULL
      ORDER BY LOWER(category)
    ''');
    return rows.map((row) => row['category'] as String).toList();
  }
}
