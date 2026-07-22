import 'dart:convert';
import 'dart:io';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SyncCoordinator {
  static const _lastExportKey = 'sync_last_export_time';
  static const _deviceIdKey = 'sync_device_id';
  static const _processedFilesKey = 'sync_processed_files';

  final DBHelper _db;

  SyncCoordinator(this._db);

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  Future<DateTime?> _getLastExportTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_lastExportKey);
    return str != null ? DateTime.parse(str) : null;
  }

  Future<void> _updateLastExportTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastExportKey, time.toIso8601String());
  }

  Future<Set<String>> getProcessedFiles() async {
    return _getProcessedFiles();
  }

  Future<Set<String>> _getProcessedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_processedFilesKey) ?? []).toSet();
  }

  Future<void> _markFileProcessed(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_processedFilesKey) ?? []).toList();
    list.add(filename);
    await prefs.setStringList(_processedFilesKey, list);
  }

  Future<SyncResult> exportChanges(Directory syncDir) async {
    final lastExport = await _getLastExportTime();
    final now = DateTime.now().toUtc();

    // Fetch changes
    final contacts = await _db.getContactsModifiedSince(lastExport);
    final interactions = await _db.getInteractionsModifiedSince(lastExport);
    final prayers = await _db.getPrayerRequestsModifiedSince(lastExport);
    final prayerLists = await _db.getPrayerListsModifiedSince(lastExport);
    final relationships = await _db.getRelationshipsModifiedSince(lastExport);

    if (contacts.isEmpty &&
        interactions.isEmpty &&
        prayers.isEmpty &&
        prayerLists.isEmpty &&
        relationships.isEmpty) {
      return const SyncResult(exportedCount: 0, importedCount: 0);
    }

    // Enrich Prayer Requests with interactionSyncId for remote resolution
    final interactionIds = prayers
        .map((p) => p.interactionId)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();

    final interactionSyncIds = <int, String>{};
    if (interactionIds.isNotEmpty) {
      final db = await _db.database;
      final chunkSize = 900;
      for (var i = 0; i < interactionIds.length; i += chunkSize) {
        final end = (i + chunkSize < interactionIds.length)
            ? i + chunkSize
            : interactionIds.length;
        final chunk = interactionIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');

        final rows = await db.query(
          'interactions',
          columns: ['id', 'syncId'],
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );

        for (final row in rows) {
          final id = row['id'] as int;
          final syncId = row['syncId'] as String?;
          if (syncId != null) {
            interactionSyncIds[id] = syncId;
          }
        }
      }
    }

    final enrichedPrayers = <Map<String, dynamic>>[];
    for (final p in prayers) {
      final map = p.toMap();
      if (p.interactionId != null) {
        final iSyncId = interactionSyncIds[p.interactionId!];
        if (iSyncId != null) {
          map['interactionSyncId'] = iSyncId;
        }
      }
      enrichedPrayers.add(map);
    }

    final data = {
      'version': 2,
      'deviceId': await getDeviceId(),
      'timestamp': now.toIso8601String(),
      'integrityCheck': 'valid',
      'contacts': contacts.map((c) => c.toMap()).toList(),
      'interactions': interactions.map((i) => i.toMap()).toList(),
      'prayerRequests': enrichedPrayers,
      'relationships': relationships.map((r) => r.toMap()).toList(),
      'prayerLists': prayerLists.map((l) {
        final map = l.toMap();
        map['contactIds'] = l.contactIds;
        return map;
      }).toList(),
    };

    final jsonStr = jsonEncode(data);
    final deviceId = await getDeviceId();
    final successTimestamp = now.millisecondsSinceEpoch;
    final filename = '${deviceId}_${successTimestamp}_data.json';

    final tempFile = File(p.join(syncDir.path, '$filename.tmp'));
    await tempFile.writeAsString(jsonStr, flush: true);
    final finalFile = File(p.join(syncDir.path, filename));
    await tempFile.rename(finalFile.path);

    await _updateLastExportTime(now);

    return SyncResult(
      exportedCount: contacts.length +
          interactions.length +
          prayers.length +
          prayerLists.length +
          relationships.length,
      importedCount: 0,
    );
  }

  Future<SyncResult> importChanges(Directory syncDir) async {
    if (!await syncDir.exists()) {
      return const SyncResult(exportedCount: 0, importedCount: 0);
    }

    final deviceId = await getDeviceId();
    final processed = await _getProcessedFiles();

    final files =
        await syncDir.list().where((f) => f is File).cast<File>().where((f) {
      final name = p.basename(f.path);
      return name.endsWith('_data.json') &&
          !name.startsWith(deviceId) &&
          !processed.contains(name);
    }).toList();

    files.sort((a, b) {
      final nameA = p.basename(a.path);
      final nameB = p.basename(b.path);
      final timeA = _extractTimestamp(nameA);
      final timeB = _extractTimestamp(nameB);
      return timeA.compareTo(timeB);
    });

    int importCount = 0;

    for (final file in files) {
      try {
        final content = await file.readAsString();
        if (content.isEmpty) continue;

        final data = jsonDecode(content);
        if (data is! Map<String, dynamic> || !data.containsKey('version')) {
          continue;
        }

        await importSyncData(data);
        await _markFileProcessed(p.basename(file.path));
        importCount++;
      } catch (e) {
        debugPrint('Error importing file ${file.path}: $e');
      }
    }

    return SyncResult(exportedCount: 0, importedCount: importCount);
  }

  int _extractTimestamp(String filename) {
    try {
      final withoutSuffix = filename.replaceAll('_data.json', '');
      final lastUnderscore = withoutSuffix.lastIndexOf('_');
      if (lastUnderscore != -1) {
        final tsPart = withoutSuffix.substring(lastUnderscore + 1);
        return int.tryParse(tsPart) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> importSyncData(Map<String, dynamic> data) async {
    // Merge Contacts
    if (data['contacts'] != null) {
      for (final item in (data['contacts'] as List)) {
        await _mergeContact(Contact.fromMap(Map<String, dynamic>.from(item)));
      }
    }

    // Merge Interactions
    if (data['interactions'] != null) {
      for (final item in (data['interactions'] as List)) {
        await _mergeInteraction(
          Interaction.fromMap(Map<String, dynamic>.from(item)),
        );
      }
    }

    // Merge Prayer Requests
    if (data['prayerRequests'] != null) {
      await _mergePrayerRequests(data['prayerRequests'] as List);
    }

    // Merge Prayer Lists
    if (data['prayerLists'] != null) {
      await _mergePrayerLists(data['prayerLists'] as List);
    }

    // Merge Relationships
    if (data['relationships'] != null) {
      await _mergeRelationships(data['relationships'] as List);
    }
  }

  Future<void> _mergeContact(Contact remote) async {
    final localContacts = await _db.getContacts(
      contactId: remote.id,
      includeDeleted: true,
    );
    final local = localContacts.isNotEmpty ? localContacts.first : null;

    if (local == null) {
      await _db.upsertContactFromSync(
        await _db.database,
        remote,
        isUpdate: false,
      );
    } else if (remote.updatedAt.isAfter(local.updatedAt)) {
      await _db.upsertContactFromSync(
        await _db.database,
        remote,
        isUpdate: true,
      );
    }
  }

  /// Returns the subset of [ids] that exist in the local `contacts` table.
  /// Used to defensively drop references to contacts that haven't been
  /// imported yet (e.g. because their creation file hasn't synced down),
  /// instead of letting a foreign-key violation abort an entire import.
  Future<Set<String>> _existingContactIds(Iterable<String> ids) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet();
    if (unique.isEmpty) return {};

    final db = await _db.database;
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

  Future<void> _mergeInteraction(Interaction remote) async {
    final db = await _db.database;
    final rows = await db.query(
      'interactions',
      where: 'syncId = ?',
      whereArgs: [remote.syncId],
    );

    final existingContactIds = await _existingContactIds(
      remote.participantIds,
    );
    final missingContactIds = remote.participantIds.toSet().difference(
          existingContactIds,
        );
    if (missingContactIds.isNotEmpty) {
      debugPrint(
        'Skipping unknown contact(s) $missingContactIds for interaction '
        '${remote.syncId}',
      );
    }
    final validParticipantIds =
        remote.participantIds.where(existingContactIds.contains).toList();

    if (rows.isEmpty) {
      if (remote.deletedAt != null) return;

      final map = remote.toMap(includeId: false, encodeAttachments: true);
      map.remove('participantIds');
      map['updatedAt'] = remote.updatedAt.toIso8601String();
      map['deletedAt'] = remote.deletedAt?.toIso8601String();
      map['syncId'] = remote.syncId;

      final id = await db.insert('interactions', map);
      await _db.replaceInteractionParticipants(db, id, validParticipantIds);
    } else {
      final localRow = rows.first;
      final localUpdated = DateTime.parse(localRow['updatedAt'] as String);
      if (remote.updatedAt.isAfter(localUpdated)) {
        final localId = localRow['id'] as int;
        final map = remote.toMap(includeId: false, encodeAttachments: true);
        map.remove('participantIds');
        map['updatedAt'] = remote.updatedAt.toIso8601String();
        map['deletedAt'] = remote.deletedAt?.toIso8601String();

        await db.update(
          'interactions',
          map,
          where: 'id = ?',
          whereArgs: [localId],
        );
        await _db.replaceInteractionParticipants(
          db,
          localId,
          validParticipantIds,
        );
      }
    }
  }

  Future<void> _mergePrayerRequests(List<dynamic> remoteList) async {
    final db = await _db.database;

    final remotePrayers = <PrayerRequest>[];
    final remoteInteractionSyncIds =
        <String, String>{}; // prayerSyncId -> interactionSyncId
    final interactionSyncIds = <String>{};

    for (final item in remoteList) {
      final map = Map<String, dynamic>.from(item);
      final remotePrayer = PrayerRequest.fromMap(map);
      remotePrayers.add(remotePrayer);

      final interactionSyncId = map['interactionSyncId'] as String?;
      if (interactionSyncId != null) {
        remoteInteractionSyncIds[remotePrayer.syncId] = interactionSyncId;
        interactionSyncIds.add(interactionSyncId);
      }
    }

    // Fetch local interaction IDs by syncId
    final localInteractionIds = <String, int>{}; // syncId -> id
    if (interactionSyncIds.isNotEmpty) {
      final interactionRows = await _db.interactionDao.chunkedQuery(
        table: 'interactions',
        inColumn: 'syncId',
        values: interactionSyncIds.toList(),
      );
      for (final row in interactionRows) {
        localInteractionIds[row['syncId'] as String] = row['id'] as int;
      }
    }

    // Fetch local prayer requests by syncId
    final localPrayerRequests = <String, Map<String, dynamic>>{};
    final syncIds = remotePrayers.map((p) => p.syncId).toList();

    if (syncIds.isNotEmpty) {
      final prayerRows = await _db.prayerRequestDao.chunkedQuery(
        table: 'prayer_requests',
        inColumn: 'syncId',
        values: syncIds,
      );
      for (final row in prayerRows) {
        localPrayerRequests[row['syncId'] as String] = row;
      }
    }

    // A prayer request's contactId is a NOT NULL foreign key, and its
    // participants are foreign keys too; skip references to contacts that
    // haven't been imported locally yet instead of letting the whole batch
    // (and every other prayer request in this file) roll back.
    final existingContactIds = await _existingContactIds({
      for (final p in remotePrayers) p.contactId,
      for (final p in remotePrayers) ...p.participantIds,
    });

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final remote in remotePrayers) {
        if (!existingContactIds.contains(remote.contactId)) {
          debugPrint(
            'Skipping prayer request ${remote.syncId}: unknown contact '
            '${remote.contactId}',
          );
          continue;
        }
        final interactionSyncId = remoteInteractionSyncIds[remote.syncId];
        int? localInteractionId;
        if (interactionSyncId != null) {
          localInteractionId = localInteractionIds[interactionSyncId];
        }

        final localRow = localPrayerRequests[remote.syncId];

        if (localRow == null) {
          if (remote.deletedAt != null) continue;

          final map = remote.toMap(includeId: false);
          map.remove('participantIds');
          map['updatedAt'] = remote.updatedAt.toIso8601String();
          map['deletedAt'] = remote.deletedAt?.toIso8601String();
          map['syncId'] = remote.syncId;
          if (localInteractionId != null) {
            map['interactionId'] = localInteractionId;
          } else {
            map.remove('interactionId');
          }

          batch.insert('prayer_requests', map);
        } else {
          final localUpdated = DateTime.parse(localRow['updatedAt'] as String);
          if (remote.updatedAt.isAfter(localUpdated)) {
            final localId = localRow['id'] as int;
            final map = remote.toMap(includeId: false);
            map.remove('participantIds');
            map['updatedAt'] = remote.updatedAt.toIso8601String();
            map['deletedAt'] = remote.deletedAt?.toIso8601String();
            if (localInteractionId != null) {
              map['interactionId'] = localInteractionId;
            } else {
              map.remove('interactionId');
            }

            batch.update(
              'prayer_requests',
              map,
              where: 'id = ?',
              whereArgs: [localId],
            );
          }
        }
      }

      final results = await batch.commit();

      // Now handle participants - this needs to be done after the first batch
      // because we need the generated IDs for new prayer requests
      final participantBatch = txn.batch();

      int index = 0;
      for (final remote in remotePrayers) {
        if (!existingContactIds.contains(remote.contactId)) continue;

        final localRow = localPrayerRequests[remote.syncId];
        final validParticipantIds =
            remote.participantIds.where(existingContactIds.contains);

        if (localRow == null) {
          if (remote.deletedAt != null) continue;

          final localId = results[index] as int;
          index++;

          participantBatch.delete(
            'prayer_request_participants',
            where: 'prayerRequestId = ?',
            whereArgs: [localId],
          );

          for (final participantId in validParticipantIds) {
            participantBatch.insert('prayer_request_participants', {
              'prayerRequestId': localId,
              'contactId': participantId,
            });
          }
        } else {
          final localUpdated = DateTime.parse(localRow['updatedAt'] as String);
          if (remote.updatedAt.isAfter(localUpdated)) {
            final localId = localRow['id'] as int;
            index++;

            participantBatch.delete(
              'prayer_request_participants',
              where: 'prayerRequestId = ?',
              whereArgs: [localId],
            );

            for (final participantId in validParticipantIds) {
              participantBatch.insert('prayer_request_participants', {
                'prayerRequestId': localId,
                'contactId': participantId,
              });
            }
          }
        }
      }

      await participantBatch.commit(noResult: true);
    });
  }

  Future<void> _mergePrayerLists(List<dynamic> remoteLists) async {
    final db = await _db.database;

    final remotePrayerLists = remoteLists
        .map((item) => PrayerList.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    final remoteIds = remotePrayerLists.map((list) => list.id).toList();

    // Fetch existing local lists in chunks
    final existingRows = await _db.prayerListDao.chunkedQuery(
      table: 'prayer_lists',
      inColumn: 'id',
      values: remoteIds,
    );

    // Create lookup map for existing lists
    final localLists = {
      for (final row in existingRows)
        row['id'] as String: PrayerList.fromMap(row)
    };

    for (final remoteList in remotePrayerLists) {
      bool shouldUpdate = false;
      final localList = localLists[remoteList.id];
      if (localList == null) {
        if (remoteList.deletedAt == null) {
          shouldUpdate = true;
        }
      } else {
        if (remoteList.updatedAt.isAfter(localList.updatedAt)) {
          shouldUpdate = true;
        }
      }

      if (shouldUpdate) {
        await _db.upsertPrayerListFromSync(db, remoteList);
      }
    }
  }

  Future<void> _mergeRelationships(List<dynamic> remoteRels) async {
    for (final item in remoteRels) {
      final remote = Relationship.fromMap(Map<String, dynamic>.from(item));

      final existingContactIds = await _existingContactIds([
        remote.sourceContactId,
        remote.targetContactId,
      ]);
      if (!existingContactIds.contains(remote.sourceContactId) ||
          !existingContactIds.contains(remote.targetContactId)) {
        debugPrint(
          'Skipping relationship ${remote.sourceContactId} -> '
          '${remote.targetContactId}: unknown contact(s)',
        );
        continue;
      }

      final existing = await _db.relationshipDao.getRelationshipsForContact(
        remote.sourceContactId,
      );
      final match = existing.any(
        (r) =>
            r.targetContactId == remote.targetContactId &&
            r.type == remote.type,
      );

      if (!match) {
        await _db.relationshipDao.upsertRelationship(
          Relationship(
            sourceContactId: remote.sourceContactId,
            targetContactId: remote.targetContactId,
            type: remote.type,
            notes: remote.notes,
            updatedAt: remote.updatedAt,
          ),
        );
      }
    }
  }
}

class SyncResult {
  final int exportedCount;
  final int importedCount;
  const SyncResult({required this.exportedCount, required this.importedCount});
}
