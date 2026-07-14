import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../base_dao.dart';

class InteractionDao extends BaseDao {
  InteractionDao(super.dbHelper);

  Future<Interaction> insertInteraction(Interaction interaction) async {
    final db = await database;
    return await db.transaction((txn) async {
      final interactionMap = interaction.toMap(
        includeId: false,
        encodeAttachments: true,
      );
      interactionMap.remove('participantIds');
      interactionMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      interactionMap['deletedAt'] = null;

      final id = await txn.insert('interactions', interactionMap);
      await replaceInteractionParticipants(txn, id, interaction.participantIds);

      return interaction.copyWith(id: id);
    });
  }

  Future<void> updateInteraction(Interaction interaction) async {
    final db = await database;
    await db.transaction((txn) async {
      final interactionMap = interaction.toMap(
        includeId: false,
        encodeAttachments: true,
      );
      interactionMap.remove('participantIds');
      interactionMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      interactionMap['deletedAt'] = null;

      await txn.update(
        'interactions',
        interactionMap,
        where: 'id = ?',
        whereArgs: [interaction.id],
      );

      await replaceInteractionParticipants(
        txn,
        interaction.id!,
        interaction.participantIds,
      );
    });
  }

  Future<void> deleteInteraction(int id) async {
    final db = await database;
    await db.update(
      'interactions',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceInteractionParticipants(
    DatabaseExecutor txn,
    int interactionId,
    List<String> participantIds,
  ) async {
    await txn.delete(
      'interaction_participants',
      where: 'interactionId = ?',
      whereArgs: [interactionId],
    );

    final uniqueParticipants = participantIds.toSet();
    final batch = txn.batch();
    for (final participant in uniqueParticipants) {
      batch.insert(
          'interaction_participants',
          {
            'interactionId': interactionId,
            'contactId': participant,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceInteractionsForContact(
    DatabaseExecutor txn,
    Contact contact,
  ) async {
    final existingRows = await txn.query(
      'interaction_participants',
      columns: ['interactionId'],
      where: 'contactId = ?',
      whereArgs: [contact.id],
    );
    final existingInteractionIds =
        existingRows.map((row) => row['interactionId'] as int).toSet();

    if (existingInteractionIds.isNotEmpty) {
      await txn.delete(
        'interaction_participants',
        where: 'contactId = ?',
        whereArgs: [contact.id],
      );
    }

    for (final interaction in contact.interactions) {
      final participants = {
        ...interaction.participantIds,
        contact.id,
      }.where((id) => id.trim().isNotEmpty).toList();

      final interactionMap = interaction.toMap(
        includeId: false,
        encodeAttachments: true,
      );
      interactionMap.remove('participantIds');
      interactionMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();

      int interactionId = -1;
      bool exists = false;

      if (interaction.id != null) {
        final count = await txn.update(
          'interactions',
          interactionMap,
          where: 'id = ?',
          whereArgs: [interaction.id],
        );
        if (count > 0) {
          interactionId = interaction.id!;
          exists = true;
        }
      }

      if (!exists) {
        final existingRows = await txn.query(
          'interactions',
          columns: ['id'],
          where: 'syncId = ?',
          whereArgs: [interaction.syncId],
        );

        if (existingRows.isNotEmpty) {
          interactionId = existingRows.first['id'] as int;
          await txn.update(
            'interactions',
            interactionMap,
            where: 'id = ?',
            whereArgs: [interactionId],
          );
        } else {
          interactionId = await txn.insert('interactions', interactionMap);
        }
      }

      await replaceInteractionParticipants(txn, interactionId, participants);
    }

    await removeOrphanInteractions(txn);
  }

  Future<void> removeOrphanInteractions(DatabaseExecutor txn) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.update(
      'interactions',
      {'deletedAt': now, 'updatedAt': now},
      where:
          'NOT EXISTS (SELECT 1 FROM interaction_participants WHERE interaction_participants.interactionId = interactions.id) AND deletedAt IS NULL',
    );
  }

  Future<Map<String, List<Interaction>>> getInteractionsForContacts(
    List<String> contactIds, {
    bool isFetchAllActive = false,
  }) async {
    final dbInstance = await database;
    final List<Map<String, Object?>> participantRows;

    if (isFetchAllActive) {
      participantRows = await dbInstance.rawQuery('''
        SELECT ip.contactId, i.*
        FROM interaction_participants ip
        JOIN interactions i ON ip.interactionId = i.id
        JOIN contacts c ON ip.contactId = c.id
        WHERE c.deletedAt IS NULL AND i.deletedAt IS NULL
        ORDER BY i.occurredAt DESC
      ''');
    } else {
      participantRows = [];
      const int batchSize = 900;
      for (var i = 0; i < contactIds.length; i += batchSize) {
        final end = (i + batchSize < contactIds.length)
            ? i + batchSize
            : contactIds.length;
        final chunk = contactIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');

        final rows = await dbInstance.rawQuery('''
          SELECT ip.contactId, i.*
          FROM interaction_participants ip
          JOIN interactions i ON ip.interactionId = i.id
          WHERE ip.contactId IN ($placeholders) AND i.deletedAt IS NULL
          ORDER BY i.occurredAt DESC
        ''', chunk);
        participantRows.addAll(rows);
      }
    }
    final fetchedInteractionIds =
        participantRows.map((r) => r['id'] as int).toSet();
    final allParticipantsMap = await getParticipantsForInteractions(
      fetchedInteractionIds,
    );

    final interactionsByContact = <String, List<Interaction>>{};
    for (final row in participantRows) {
      final cId = row['contactId'] as String;
      final iId = row['id'] as int;
      final interactionMap = Map<String, dynamic>.from(row);
      interactionMap.remove('contactId');
      interactionMap['participantIds'] = allParticipantsMap[iId] ?? [];

      interactionsByContact
          .putIfAbsent(cId, () => [])
          .add(Interaction.fromMap(interactionMap));
    }

    return interactionsByContact;
  }

  Future<Map<int, List<String>>> getParticipantsForInteractions(
    Iterable<int> interactionIds,
  ) async {
    if (interactionIds.isEmpty) return {};
    final rows = await chunkedQuery(
      table: 'interaction_participants',
      inColumn: 'interactionId',
      values: interactionIds.toList(),
    );

    final participantsByInteraction = <int, List<String>>{};
    for (final row in rows) {
      final interactionId = row['interactionId'] as int;
      final participantId = row['contactId'] as String;
      participantsByInteraction.putIfAbsent(interactionId, () => []);
      participantsByInteraction[interactionId]!.add(participantId);
    }

    return participantsByInteraction;
  }

  Future<List<Interaction>> getInteractions({
    DateTime? start,
    DateTime? end,
    String? contactId,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    final dbInstance = await database;
    final where = <String>[includeDeleted ? '1 = 1' : 'deletedAt IS NULL'];
    final whereArgs = <Object?>[];

    if (contactId != null) {
      final interactionIdRows = await dbInstance.query(
        'interaction_participants',
        columns: ['interactionId'],
        where: 'contactId = ?',
        whereArgs: [contactId],
      );
      final interactionIds =
          interactionIdRows.map((r) => r['interactionId'] as int).toList();
      if (interactionIds.isEmpty) return [];

      final placeholders = List.filled(interactionIds.length, '?').join(',');
      where.add('id IN ($placeholders)');
      whereArgs.addAll(interactionIds);
    }

    if (start != null) {
      where.add('occurredAt >= ?');
      whereArgs.add(start.toIso8601String());
    }

    if (end != null) {
      where.add('occurredAt <= ?');
      whereArgs.add(end.toIso8601String());
    }

    if (updatedSince != null) {
      where.add('updatedAt > ?');
      whereArgs.add(updatedSince.toIso8601String());
    }

    final rows = await dbInstance.query(
      'interactions',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'occurredAt DESC',
    );

    if (rows.isEmpty) return [];

    final validIds = rows.map((r) => r['id'] as int).toSet();
    final participantsByInteraction = await getParticipantsForInteractions(
      validIds,
    );

    return rows.map((row) {
      final interactionMap = Map<String, dynamic>.from(row);
      interactionMap['participantIds'] =
          participantsByInteraction[row['id'] as int] ?? const <String>[];
      return Interaction.fromMap(interactionMap);
    }).toList();
  }

  Future<Interaction?> getInteractionById(int interactionId) async {
    final dbInstance = await database;
    final rows = await dbInstance.query(
      'interactions',
      where: 'id = ? AND deletedAt IS NULL',
      whereArgs: [interactionId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final participantsByInteraction = await getParticipantsForInteractions({
      interactionId,
    });
    final interactionMap = Map<String, dynamic>.from(rows.first);
    interactionMap['participantIds'] =
        participantsByInteraction[interactionId] ?? const <String>[];
    return Interaction.fromMap(interactionMap);
  }

  Future<bool> interactionExists({
    required String contactId,
    required DateTime occurredAt,
    required String summary,
  }) async {
    final dbInstance = await database;
    final rows = await dbInstance.rawQuery(
      '''
      SELECT i.id FROM interactions i
      JOIN interaction_participants ip ON i.id = ip.interactionId
      WHERE ip.contactId = ? AND i.occurredAt = ? AND i.summary = ? AND i.deletedAt IS NULL
      LIMIT 1
    ''',
      [contactId, occurredAt.toIso8601String(), summary],
    );

    return rows.isNotEmpty;
  }

  Future<List<InteractionDuplicateGroup>> findDuplicateInteractions() async {
    // Fetch all active interactions
    final activeInteractions = await getInteractions(includeDeleted: false);
    if (activeInteractions.isEmpty) return const [];

    // Group by occurredAt (UTC string representation) and normalized summary
    final Map<String, List<Interaction>> groups = {};
    for (final i in activeInteractions) {
      final occurredKey = i.occurredAt.toUtc().toIso8601String();
      final summaryKey = i.summary.trim().toLowerCase();
      final key = '${occurredKey}_$summaryKey';
      groups.putIfAbsent(key, () => []).add(i);
    }

    final List<InteractionDuplicateGroup> duplicateGroups = [];

    for (final entry in groups.entries) {
      final group = entry.value;
      if (group.length < 2) continue;

      // Sort by id ascending so the oldest DB row is kept as primary
      group.sort((a, b) {
        if (a.id == null && b.id != null) return 1;
        if (a.id != null && b.id == null) return -1;
        if (a.id != null && b.id != null) return a.id!.compareTo(b.id!);
        return a.updatedAt.compareTo(b.updatedAt);
      });

      final primary = group.first;
      final duplicates = group.sublist(1);
      duplicateGroups.add(
        InteractionDuplicateGroup(primary: primary, duplicates: duplicates),
      );
    }

    return duplicateGroups;
  }

  Future<int> deDuplicateInteractions() async {
    final db = await database;
    final duplicateGroups = await findDuplicateInteractions();
    if (duplicateGroups.isEmpty) return 0;

    int mergedCount = 0;

    await db.transaction((txn) async {
      for (final groupInfo in duplicateGroups) {
        var primary = groupInfo.primary;
        final duplicates = groupInfo.duplicates;

        // Merge properties
        final participantIds = primary.participantIds.toSet();
        final attachments = [...primary.attachments];
        var markForPrayer = primary.markForPrayer;
        var notes = primary.notes;
        var durationMinutes = primary.durationMinutes;
        var location = primary.location;
        var followUpAt = primary.followUpAt;

        for (final dup in duplicates) {
          participantIds.addAll(dup.participantIds);
          for (final att in dup.attachments) {
            if (!attachments.any((a) => a.uri == att.uri)) {
              attachments.add(att);
            }
          }
          if (dup.markForPrayer) {
            markForPrayer = true;
          }
          if (dup.notes != null && dup.notes!.isNotEmpty) {
            if (notes == null || notes.isEmpty) {
              notes = dup.notes;
            } else if (notes != dup.notes) {
              notes = '$notes\n${dup.notes}';
            }
          }
          if (dup.durationMinutes != null) {
            if (durationMinutes == null ||
                dup.durationMinutes! > durationMinutes) {
              durationMinutes = dup.durationMinutes;
            }
          }
          if (location == null || location.isEmpty) {
            location = dup.location;
          }
          followUpAt ??= dup.followUpAt;
        }

        // Update primary interaction with merged properties
        final now = DateTime.now().toUtc();
        primary = primary.copyWith(
          participantIds: participantIds.toList(),
          attachments: attachments,
          markForPrayer: markForPrayer,
          notes: notes,
          durationMinutes: durationMinutes,
          location: location,
          followUpAt: followUpAt,
          updatedAt: now,
        );

        final interactionMap = primary.toMap(
          includeId: false,
          encodeAttachments: true,
        );
        interactionMap.remove('participantIds');
        interactionMap['updatedAt'] = now.toIso8601String();
        interactionMap['deletedAt'] = null;

        await txn.update(
          'interactions',
          interactionMap,
          where: 'id = ?',
          whereArgs: [primary.id],
        );

        await replaceInteractionParticipants(
          txn,
          primary.id!,
          primary.participantIds,
        );

        // Soft delete the duplicates
        final nowStr = now.toIso8601String();
        if (duplicates.isNotEmpty) {
          final dupIds = duplicates.map((d) => d.id).toList();

          // SQLite has a limit on variables, so chunk the updates if there are many duplicates.
          // BaseDao provides chunkedQuery, but we need to do updates, so we can use batch or chunking directly.
          const batchSize = 900;
          for (var i = 0; i < dupIds.length; i += batchSize) {
            final end =
                (i + batchSize < dupIds.length) ? i + batchSize : dupIds.length;
            final chunk = dupIds.sublist(i, end);
            final placeholders = List.filled(chunk.length, '?').join(',');

            await txn.update(
              'interactions',
              {'deletedAt': nowStr, 'updatedAt': nowStr},
              where: 'id IN ($placeholders)',
              whereArgs: chunk,
            );
          }
          mergedCount += duplicates.length;
        }
      }
    });

    return mergedCount;
  }
}
