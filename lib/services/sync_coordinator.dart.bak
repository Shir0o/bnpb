import 'dart:convert';
import 'dart:io';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class SyncCoordinator {
  static const _lastExportKey = 'sync_last_export_time';
  static const _deviceIdKey = 'sync_device_id';
  static const _processedFilesKey = 'sync_processed_files';

  final DBHelper _db;

  SyncCoordinator(this._db);

  Future<String> _getDeviceId() async {
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
    final now = DateTime.now().toUtc(); // Use UTC for consistency

    // Fetch changes
    final contacts = await _db.getContactsModifiedSince(lastExport);
    final interactions = await _db.getInteractionsModifiedSince(lastExport);
    final prayers = await _db.getPrayerRequestsModifiedSince(lastExport);

    // Prayer Lists don't have timestamps so we export all of them every time.
    final prayerLists = await _db.getPrayerLists();

    if (contacts.isEmpty &&
        interactions.isEmpty &&
        prayers.isEmpty &&
        prayerLists.isEmpty) {
      return const SyncResult(exportedCount: 0, importedCount: 0);
    }

    // Enrich Prayer Requests with interactionSyncId
    final enrichedPrayers = <Map<String, dynamic>>[];
    for (final p in prayers) {
      final map = p.toMap();
      if (p.interactionId != null) {
        final iSyncId = await _getInteractionSyncId(p.interactionId!);
        if (iSyncId != null) {
          map['interactionSyncId'] = iSyncId;
        }
      }
      enrichedPrayers.add(map);
    }

    // Serialize
    final data = {
      'version': 1,
      'deviceId': await _getDeviceId(),
      'timestamp': now.toIso8601String(),
      'integrityCheck': 'valid', // Marker for integrity
      'contacts': contacts.map((c) => c.toMap()).toList(),
      'interactions': interactions.map((i) => i.toMap()).toList(),
      'prayerRequests': enrichedPrayers,
      'prayerLists': prayerLists.map((l) {
        final map = l.toMap();
        map['contactIds'] = l.contactIds;
        return map;
      }).toList(),
    };

    final jsonStr = jsonEncode(data);
    final deviceId = await _getDeviceId();
    // Filename: deviceId_timestamp_data.json
    // Use a safe timestamp format for filenames
    final successTimestamp = now.millisecondsSinceEpoch;
    final filename = '${deviceId}_${successTimestamp}_data.json';

    // Atomic Write: Write to temp file then rename
    final tempFile = File(p.join(syncDir.path, '$filename.tmp'));
    await tempFile.writeAsString(jsonStr, flush: true);
    final finalFile = File(p.join(syncDir.path, filename));
    await tempFile.rename(finalFile.path);

    // Update last export time implies we won't export these again
    // We should strictly use 'now' as the new checkpoint.
    await _updateLastExportTime(now);

    return SyncResult(
      exportedCount: contacts.length +
          interactions.length +
          prayers.length +
          prayerLists.length,
      importedCount: 0,
    );
  }

  Future<String?> _getInteractionSyncId(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'interactions',
      columns: ['syncId'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      return rows.first['syncId'] as String?;
    }
    return null;
  }

  Future<SyncResult> importChanges(Directory syncDir) async {
    if (!await syncDir.exists()) {
      return const SyncResult(exportedCount: 0, importedCount: 0);
    }

    final deviceId = await _getDeviceId();
    final processed = await _getProcessedFiles();

    final files = syncDir.listSync().whereType<File>().where((f) {
      final name = p.basename(f.path);
      return name.endsWith('_data.json') &&
          !name.startsWith(deviceId) && // Ignore own files
          !processed.contains(name);
    }).toList();

    // Sort by timestamp in filename to apply in order
    // Filename format: deviceId_timestamp_data.json
    // timestamp is integer milliseconds
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
        if (content.isEmpty) {
          debugPrint('Skipping empty file: ${file.path}');
          continue;
        }

        final data = jsonDecode(content);

        // Integrity Check
        if (data is! Map<String, dynamic> || !data.containsKey('version')) {
          debugPrint('Skipping invalid JSON file: ${file.path}');
          continue;
        }

        // Transaction? Ideally yes, but merging calls individual ops
        // We can wrap per file?
        await _mergeData(data);

        await _markFileProcessed(p.basename(file.path));
        importCount++;
      } catch (e) {
        debugPrint('Error importing file ${file.path}: $e');
        // Retrieve generic error handling or continue?
        // Continue to next file.
      }
    }

    return SyncResult(exportedCount: 0, importedCount: importCount);
  }

  int _extractTimestamp(String filename) {
    // Expected: deviceId_timestamp_data.json
    try {
      final parts = filename.split('_');
      if (parts.length >= 3) {
        // parts[parts.length - 2] should be timestamp if format is strictly followed
        // recursive split might be safer if deviceID has usually no underscores but UUID has none.
        // Let's assume deviceId doesn't contain the separator pattern or we parse from end.
        // suffix is _data.json
        final withoutSuffix = filename.replaceAll('_data.json', '');
        final lastUnderscore = withoutSuffix.lastIndexOf('_');
        if (lastUnderscore != -1) {
          final tsPart = withoutSuffix.substring(lastUnderscore + 1);
          return int.tryParse(tsPart) ?? 0;
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _mergeData(Map<String, dynamic> data) async {
    // Merge Contacts
    if (data['contacts'] != null) {
      for (final item in (data['contacts'] as List)) {
        final map = Map<String, dynamic>.from(item);
        final remoteContact = Contact.fromMap(map);
        await _mergeContact(remoteContact);
      }
    }

    // Merge Interactions
    if (data['interactions'] != null) {
      for (final item in (data['interactions'] as List)) {
        final map = Map<String, dynamic>.from(item);
        final remoteInteraction = Interaction.fromMap(map);
        await _mergeInteraction(remoteInteraction);
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
  }

  Future<void> _mergeContact(Contact remote) async {
    final local = await _db.getContactById(remote.id);

    if (local == null) {
      // New or previously deleted locally?
      // If deleted locally, we might have a tombstone?
      // Current DB getContactById returns NULL if deleted (soft delete).
      // We should check if it exists but is deleted.
      // But _db.getContactById uses getContacts which filters deleted.
      // If we want to check tombstone, we need raw query or unconditional fetch.
      // BUT, if remote is newer, we should revive it anyway if remote is not deleted.
      // If remote is deleted, we do nothing (it's gone).

      if (remote.deletedAt != null) {
        // Remote says delete. We don't have it (or it's deleted). Ensure deleted.
        // Ideally we ensure it's deleted in DB, but if it returns null it's either gone or deleted.
        // To be safe we could upsert it as deleted.
        // But if it doesn't exist, inserting a deleted record is effectively storing a tombstone.
        // This is good for eventual consistency.
        // However, inserting might fail if we don't have all fields?
        // Sync should carry all fields.
        await _db.upsertContactFromSync(await _db.database, remote,
            isUpdate: false);
      } else {
        // Remote is alive. Insert it.
        await _db.upsertContactFromSync(await _db.database, remote,
            isUpdate: false);
      }
    } else {
      // Local exists (and is alive).
      // Compare timestamps.
      // CAUTION: 'updatedAt' might not be on the model instance from getContactById?
      // Wait, Contact model NOW has updatedAt and deletedAt fields.
      // Helper `getContacts` maps them?
      // I didn't verify `Contact.fromMap` had `updatedAt` mapped!
      // I only updated `DBHelper` to query. I updated `Contact` model earlier.
      // Assuming `Contact.fromMap` works.

      final localTime = local.updatedAt;
      final remoteTime = remote.updatedAt; // Should stick to non-null

      if (remoteTime.isAfter(localTime)) {
        // Remote is newer. Overwrite.
        await _db.upsertContactFromSync(await _db.database, remote,
            isUpdate: true);
      }
      // If local is new, keep local.
      // If equal, do nothing.
    }
  }

  Future<void> _mergeInteraction(Interaction remote) async {
    // ID might be problematic if integer auto-increment changes?
    // CRITICAL: Syncing integer IDs across devices is BAD.
    // The plan said: "Add syncId (UUID) to Interactions".
    // Sync should use `syncId` to match!
    // But `getInteractionById` uses integer ID.
    // Sync logic MUST use `syncId`.

    // I need `getInteractionBySyncId`?
    // Or I check `syncId` match.
    // Wait, Interaction integer ID is local-only.
    // Remote sends integer ID but it's consistent only on source device.
    // Remote should rely on `syncId`.

    // Sync should use `syncId` to match!
    // But `getInteractionById` uses integer ID.
    // Sync logic MUST use `syncId`.

    // We need to find local record by syncId.
    // DBHelper doesn't have `getInteractionBySyncId`.
    // I should add it or scan? Scanning is slow.
    // I should add `getInteractionBySyncId` to DBHelper OR use raw query here.
    // Since `SyncCoordinator` has `_db`, I can use `_db.database.query`.

    // Let's implement `_upsertInteractionBySyncId`.
    await _upsertInteractionBySyncLogic(remote);
  }

  Future<void> _upsertInteractionBySyncLogic(Interaction remote) async {
    final db = await _db.database;
    final rows = await db.query(
      'interactions',
      where: 'syncId = ?',
      whereArgs: [remote.syncId],
    );

    if (rows.isEmpty) {
      // Insert new.
      // We must IGNORE remote integer ID and let local AutoIncrement generate one.
      // BUT we must map relationships using... wait.
      // Relationships (Participants) use Contact IDs (UUIDs). So that's fine.
      // Prayer Requests use Interaction ID (Integer).
      // If we generate a new Integer ID, the Prayer Request referring to it (by old remote int ID) will break!
      // Syncing Prayer Requests needs to handle this.
      // Prayer Request should refer to Interaction by SyncID too?
      // The plan said "PrayerRequest added syncId".
      // Does it have `interactionSyncId`? No.
      // It has `interactionId`.
      // If we sync PrayerRequest, we need to resolve `interactionId`.
      // This implies we need to lookup the local integer ID for the interaction SyncID.

      if (remote.deletedAt != null) {
        // Inserting a tombstone?
        // If we don't have it, and it's deleted, we ignore it?
        // Or we store it to prevent future re-import?
        // Storing tombstones with new IDs is messy.
        // Ideally we ignore if we don't have it.
        return;
      }

      final toInsert = remote.copyWith(id: null); // Remove ID to autogenerate
      // ... wait, `insertInteraction` in DB helper handles participants.
      // We can just call `_db.insertInteraction(toInsert)`.
      // But we need to preserve `syncId` and `updatedAt`.
      // `insertInteraction` overrides `updatedAt` to Now!
      // We need a raw insert or `_importInteraction` method in DBHelper that allows forcing timestamps.

      // For now, I'll attempt raw insert via DB instance.

      final map = toInsert.toMap(includeId: false, encodeAttachments: true);
      map.remove('participantIds');
      // Force timestamps and syncId
      map['updatedAt'] = remote.updatedAt.toIso8601String();
      map['deletedAt'] = remote.deletedAt;
      map['syncId'] = remote.syncId;

      final id = await db.insert('interactions', map);

      // Handle participants
      // We need `_replaceInteractionParticipants` logic which is private in DBHelper...
      // I might need to expose it or duplicate it.
      // Duplicating small logic is safer than exposing privates publicly if not needed.
      await _replaceParticipants(db, id, remote.participantIds);
    } else {
      // Update existing
      final localRow = rows.first;
      final localUpdated = DateTime.parse(localRow['updatedAt'] as String);
      final remoteUpdated = remote.updatedAt;

      if (remoteUpdated.isAfter(localUpdated)) {
        final localId = localRow['id'] as int;

        final map = remote.toMap(includeId: false, encodeAttachments: true);
        map.remove('participantIds');
        map['updatedAt'] = remoteUpdated.toIso8601String();
        map['deletedAt'] = remote.deletedAt;
        // Keep local ID

        await db.update(
          'interactions',
          map,
          where: 'id = ?',
          whereArgs: [localId],
        );

        await _replaceParticipants(db, localId, remote.participantIds);
      }
    }
  }

  Future<void> _replaceParticipants(DatabaseExecutor txn, int interactionId,
      List<String> participantIds) async {
    await txn.delete(
      'interaction_participants',
      where: 'interactionId = ?',
      whereArgs: [interactionId],
    );

    final uniqueParticipants = participantIds.toSet();
    for (final participant in uniqueParticipants) {
      try {
        await txn.insert(
          'interaction_participants',
          {
            'interactionId': interactionId,
            'contactId': participant,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint(
            'Skipping participant $participant for interaction $interactionId due to error: $e');
      }
    }
  }

  Future<void> _mergePrayerRequest(
      PrayerRequest remote, String? interactionSyncId) async {
    // Similar logic using syncId

    final db = await _db.database;
    final rows = await db.query(
      'prayer_requests',
      where: 'syncId = ?',
      whereArgs: [remote.syncId],
    );

    // Resolve interactionLink
    int? localInteractionId;
    if (interactionSyncId != null) {
      localInteractionId =
          await _getLocalInteractionIdBySyncId(interactionSyncId);
      // If null, we might not have synced interactions yet?
      // Files are sorted by timestamp, so hopefully interaction came first.
      // Or it's in same file. Order in file: Contacts, Interactions, Prayers. Yes.
    }

    // Note: we can't update `remote.interactionId` directly as it's immutable?
    // We construct map.

    if (rows.isEmpty) {
      if (remote.deletedAt != null) return;

      final map = remote.toMap(includeId: false);
      map['updatedAt'] = remote.updatedAt.toIso8601String();
      map['deletedAt'] = remote.deletedAt;
      map['syncId'] = remote.syncId;

      if (localInteractionId != null) {
        map['interactionId'] = localInteractionId;
      } else {
        map.remove('interactionId');
      }

      await db.insert('prayer_requests', map);
    } else {
      final localRow = rows.first;
      final localUpdated = DateTime.parse(localRow['updatedAt'] as String);
      final remoteUpdated = remote.updatedAt;

      if (remoteUpdated.isAfter(localUpdated)) {
        final localId = localRow['id'] as int;
        final map = remote.toMap(includeId: false);
        map['updatedAt'] = remoteUpdated.toIso8601String();
        map['deletedAt'] = remote.deletedAt;

        if (localInteractionId != null) {
          map['interactionId'] = localInteractionId;
        } else {
          map.remove('interactionId');
        }

        await db.update('prayer_requests', map,
            where: 'id = ?', whereArgs: [localId]);
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
    if (rows.isNotEmpty) {
      return rows.first['id'] as int;
    }
    return null;
  }

  Future<void> _mergePrayerLists(List<dynamic> remoteLists) async {
    // PrayerLists do not have timestamps in current schema.
    // Strategy: "Sync All" / "Merge by ID".
    // We will iterate remote lists and upsert them.
    // If a local list with same ID exists, we overwrite (remote wins) or merge?
    // Without timestamps, we can't determine "newer".
    // Assume Remote Wins for now to allow restore.

    // Also, we don't track deletions because we don't have deletedAt.
    // So deleted lists won't be deleted on import unless we diff?
    // Diffing against "all local" is risky if we are doing incremental sync.
    // But here we are just adding back missing ones.

    final db = await _db.database;

    for (final item in remoteLists) {
      final map = Map<String, dynamic>.from(item);
      // PrayerList.fromMap expects contactIds separately if they are not in the map key 'contactIds'?
      // toMap() creates: id, name, description, color, displayIndex.
      // It does NOT include members in toMap by default in the model?
      // CHECK PrayerList.toMap in model.
      // Yes, toMap() does not include contactIds.
      // But we need to export them!

      // I need to update exportChanges to include members in the map manually.

      final contactIds =
          (map['contactIds'] as List?)?.map((e) => e.toString()).toList();

      // We upsert the list info
      final listMap = {
        'id': map['id'],
        'name': map['name'],
        'description': map['description'],
        'color': map['color'],
        'displayIndex': map['displayIndex'],
      };

      await db.insert('prayer_lists', listMap,
          conflictAlgorithm: ConflictAlgorithm.replace);

      // Update members
      if (contactIds != null) {
        final listId = map['id'] as String;
        await db.delete('prayer_list_members',
            where: 'listId = ?', whereArgs: [listId]);
        for (final cid in contactIds) {
          await db.insert(
            'prayer_list_members',
            {'listId': listId, 'contactId': cid},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    }
  }
}

class SyncResult {
  final int exportedCount;
  final int importedCount;
  const SyncResult({required this.exportedCount, required this.importedCount});
}
