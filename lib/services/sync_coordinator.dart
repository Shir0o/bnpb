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
    final relationships = await _db.getAllRelationships();

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
      for (final item in (data['prayerRequests'] as List)) {
        final map = Map<String, dynamic>.from(item);
        final remotePrayer = PrayerRequest.fromMap(map);
        final interactionSyncId = map['interactionSyncId'] as String?;
        await _mergePrayerRequest(remotePrayer, interactionSyncId);
      }
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

  Future<void> _mergeInteraction(Interaction remote) async {
    final db = await _db.database;
    final rows = await db.query(
      'interactions',
      where: 'syncId = ?',
      whereArgs: [remote.syncId],
    );

    if (rows.isEmpty) {
      if (remote.deletedAt != null) return;

      final map = remote.toMap(includeId: false, encodeAttachments: true);
      map.remove('participantIds');
      map['updatedAt'] = remote.updatedAt.toIso8601String();
      map['deletedAt'] = remote.deletedAt?.toIso8601String();
      map['syncId'] = remote.syncId;

      final id = await db.insert('interactions', map);
      await _db.replaceInteractionParticipants(db, id, remote.participantIds);
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
          remote.participantIds,
        );
      }
    }
  }

  Future<void> _mergePrayerRequest(
    PrayerRequest remote,
    String? interactionSyncId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      'prayer_requests',
      where: 'syncId = ?',
      whereArgs: [remote.syncId],
    );

    int? localInteractionId;
    if (interactionSyncId != null) {
      localInteractionId = await _getLocalInteractionIdBySyncId(
        interactionSyncId,
      );
    }

    if (rows.isEmpty) {
      if (remote.deletedAt != null) return;

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

      final id = await db.insert('prayer_requests', map);
      await _db.replacePrayerRequestParticipants(db, id, remote.participantIds);
    } else {
      final localRow = rows.first;
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

        await db.update(
          'prayer_requests',
          map,
          where: 'id = ?',
          whereArgs: [localId],
        );
        await _db.replacePrayerRequestParticipants(
          db,
          localId,
          remote.participantIds,
        );
      }
    }
  }

  Future<int?> _getLocalInteractionIdBySyncId(String syncId) async {
    final db = await _db.database;
    final rows = await db.query(
      'interactions',
      columns: ['id'],
      where: 'syncId = ?',
      whereArgs: [syncId],
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return null;
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
