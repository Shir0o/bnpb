import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/contact.dart';
import '../../models/prayer_request.dart';
import '../base_dao.dart';
import '../updated_since.dart';

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

  /// Inserts one request per contact from [template], each with its own
  /// syncId and [contactIds] entry as its only participant. Returns the new
  /// row ids in the order of [contactIds].
  Future<List<int>> createForEachContact(
    PrayerRequest template,
    List<String> contactIds,
  ) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final ids = <int>[];

    await db.transaction((txn) async {
      for (final contactId in contactIds) {
        final request = template.copyWith(
          syncId: const Uuid().v4(),
          participantIds: [contactId],
        );
        final reqMap = request.toMap(includeId: false);
        reqMap.remove('participantIds');
        reqMap['updatedAt'] = now;
        reqMap['deletedAt'] = null;

        final id = await txn.insert('prayer_requests', reqMap);
        await replacePrayerRequestParticipants(txn, id, [contactId]);
        ids.add(id);
      }
    });

    return ids;
  }

  /// Moves a request to [status] in one step.
  ///
  /// - answered: answeredAt = [now], reflectionNotes = [comment].
  /// - archived: archivedAt = [now]; [comment] replaces reflectionNotes only
  ///   when given, so an answered request's notes survive archiving.
  /// - pending: clears answeredAt, archivedAt and reflectionNotes.
  Future<void> setStatus(
    int requestId,
    PrayerRequestStatus status, {
    String? comment,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toIso8601String();
    final note = comment?.trim();
    final values = <String, Object?>{
      'status': status.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    switch (status) {
      case PrayerRequestStatus.pending:
        values['answeredAt'] = null;
        values['archivedAt'] = null;
        values['reflectionNotes'] = null;
      case PrayerRequestStatus.answered:
        values['answeredAt'] = at;
        values['archivedAt'] = null;
        values['reflectionNotes'] = (note?.isEmpty ?? true) ? null : note;
      case PrayerRequestStatus.archived:
        values['archivedAt'] = at;
        if (note != null && note.isNotEmpty) values['reflectionNotes'] = note;
    }

    final db = await database;
    await db.update(
      'prayer_requests',
      values,
      where: 'id = ?',
      whereArgs: [requestId],
    );
  }

  /// Days each request was prayed for, ascending, as the earliest log time on
  /// each local calendar day (entries synced from two devices for the same day
  /// count once). Requests never prayed for are absent from the map.
  Future<Map<int, List<DateTime>>> getPrayedDates(List<int> requestIds) async {
    final rows = await chunkedQuery(
      table: 'prayer_request_prayed_log',
      inColumn: 'prayerRequestId',
      values: requestIds,
      where: 'deletedAt IS NULL',
    );

    final byRequest = <int, Map<DateTime, DateTime>>{};
    for (final row in rows) {
      final prayedAt = DateTime.parse(row['prayedAt'] as String).toLocal();
      final day = DateTime(prayedAt.year, prayedAt.month, prayedAt.day);
      final days = byRequest.putIfAbsent(
        row['prayerRequestId'] as int,
        () => {},
      );
      final earliest = days[day];
      if (earliest == null || prayedAt.isBefore(earliest)) {
        days[day] = prayedAt;
      }
    }

    return {
      for (final entry in byRequest.entries)
        entry.key: entry.value.values.toList()..sort(),
    };
  }

  /// Marks [requestId] as prayed for on the local calendar day of [now], or
  /// tombstones that day's entries if already marked. Returns whether the day
  /// is now marked.
  Future<bool> togglePrayedToday(int requestId, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toLocal();
    final stamp = DateTime.now().toUtc().toIso8601String();
    final db = await database;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'prayer_request_prayed_log',
        columns: ['id', 'prayedAt'],
        where: 'prayerRequestId = ? AND deletedAt IS NULL',
        whereArgs: [requestId],
      );
      final todayIds = rows.where((row) {
        final prayedAt = DateTime.parse(row['prayedAt'] as String).toLocal();
        return prayedAt.year == at.year &&
            prayedAt.month == at.month &&
            prayedAt.day == at.day;
      }).map((row) => row['id'] as int);

      if (todayIds.isNotEmpty) {
        final ids = todayIds.toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        await txn.update(
          'prayer_request_prayed_log',
          {'deletedAt': stamp, 'updatedAt': stamp},
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
        return false;
      }

      await txn.insert('prayer_request_prayed_log', {
        'syncId': const Uuid().v4(),
        'prayerRequestId': requestId,
        'prayedAt': at.toUtc().toIso8601String(),
        'updatedAt': stamp,
      });
      return true;
    });
  }

  /// Prayed-log rows, tombstones included, keyed by their request's syncId
  /// (local ids differ across devices) for sync and export payloads.
  Future<List<Map<String, Object?>>> getPrayedLogForSync({
    DateTime? updatedSince,
  }) async {
    final db = await database;
    var rows = await db.rawQuery('''
      SELECT * FROM (
        SELECT l.syncId, pr.syncId AS prayerRequestSyncId, l.prayedAt,
          l.updatedAt, l.deletedAt
        FROM prayer_request_prayed_log l
        JOIN prayer_requests pr ON pr.id = l.prayerRequestId
      )
      ${updatedSince != null ? 'WHERE $updatedSinceDateClause' : ''}
    ''', [if (updatedSince != null) updatedSinceDateArg(updatedSince)]);

    if (updatedSince != null) rows = rowsUpdatedAfter(rows, updatedSince);
    return rows;
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
      final idsList = idsToDelete.toList();
      for (var i = 0; i < idsList.length; i += 900) {
        final end = (i + 900 < idsList.length) ? i + 900 : idsList.length;
        final chunk = idsList.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');

        await txn.update(
          'prayer_requests',
          {'deletedAt': now, 'updatedAt': now},
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
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
      where += ' AND $updatedSinceDateClause';
      whereArgs.add(updatedSinceDateArg(updatedSince));
    }

    // With updatedSince the exact cut runs in Dart, so the limit must too.
    var rows = await db.query(
      'prayer_requests',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: updatedSince == null ? limit : null,
    );

    if (updatedSince != null) {
      rows = rowsUpdatedAfter(rows, updatedSince);
      if (limit != null) rows = rows.take(limit).toList();
    }

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
