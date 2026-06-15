import 'dart:convert';
import 'dart:io';

import '../db/db_helper.dart';
import '../models/contact.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;
import '../models/prayer_list.dart';
import 'ai/ai_services.dart';
import 'import_duplicate_detector.dart';
import 'reminder_coordinator.dart';
import 'sync_coordinator.dart';

/// Resolves a list of suspected duplicate groups in an incoming import.
/// Returning a new list replaces [incoming]; returning `null` aborts the
/// import.
typedef DuplicateReviewCallback = Future<List<Contact>?> Function(
  List<Contact> incoming,
  List<DuplicateGroup> groups,
);

class ImportService {
  final DBHelper _dbHelper = DBHelper();
  final ReminderCoordinator _reminderCoordinator = ReminderCoordinator();

  /// Best-effort: wipe the semantic search vector store so it doesn't keep
  /// pointing at contact ids that no longer exist after a destructive
  /// overwrite import. The home page will rebuild it on the next snapshot.
  Future<void> _clearSemanticIndex() async {
    try {
      await AiServices().semanticSearch.clear();
    } catch (_) {
      // Index might not be initialized yet (Ask never used). Nothing to clear.
    }
  }

  /// Imports a JSON export file (legacy list or V2 map format).
  ///
  /// When [onDuplicatesFound] is supplied and the legacy-list path detects
  /// intra-import duplicates, the callback is invoked to let the user pick
  /// merge / keep / skip per group. Returning `null` aborts the import; this
  /// method then returns `-1`.
  ///
  /// Returns the number of contacts restored, or `-1` if the user aborted at
  /// the duplicate-review step.
  Future<int> importJsonExport(
    File file, {
    DuplicateReviewCallback? onDuplicatesFound,
  }) async {
    final fileContent = await file.readAsString();
    final dynamic jsonData = jsonDecode(fileContent);

    // Check for Version 2 / Unified Sync Format (flat structure)
    if (jsonData is Map<String, dynamic> &&
        (jsonData['version'] == 2 || jsonData.containsKey('interactions'))) {
      // Overwrite behavior: clear existing data before importing.
      await _dbHelper.clearAllData();

      final coordinator = SyncCoordinator(_dbHelper);
      await coordinator.importSyncData(jsonData);
      await _reminderCoordinator.refreshAllContacts();
      final contacts = (jsonData['contacts'] as List?) ?? [];
      return contacts.length;
    }

    List<Contact> restoredContacts = [];
    List<PrayerList> restoredPrayerLists = [];

    if (jsonData is List) {
      restoredContacts = jsonData
          .map(
            (contactMap) =>
                Contact.fromMap(Map<String, dynamic>.from(contactMap as Map)),
          )
          .toList();
    } else if (jsonData is Map) {
      if (jsonData['contacts'] != null) {
        restoredContacts = (jsonData['contacts'] as List)
            .map(
              (contactMap) =>
                  Contact.fromMap(Map<String, dynamic>.from(contactMap as Map)),
            )
            .toList();
      }
      if (jsonData['prayerLists'] != null) {
        restoredPrayerLists = (jsonData['prayerLists'] as List).map((listMap) {
          final map = Map<String, dynamic>.from(listMap as Map);
          return PrayerList.fromMap(map);
        }).toList();
      }
    }

    if (restoredContacts.isEmpty) {
      throw const FormatException('No contacts found in JSON.');
    }

    if (onDuplicatesFound != null) {
      final groups = ImportDuplicateDetector().findDuplicateGroups(
        restoredContacts,
      );
      if (groups.isNotEmpty) {
        final resolved = await onDuplicatesFound(restoredContacts, groups);
        if (resolved == null) return -1;
        restoredContacts = resolved;
        if (restoredContacts.isEmpty) return 0;
      }
    }

    // Overwrite behavior: clear existing data before importing.
    await _dbHelper.clearAllData();
    await _clearSemanticIndex();

    // Pass 1: Insert all contact rows first (without relations to avoid FK issues).
    // Use a batched transaction to avoid N+1 query performance hits.
    final db = await _dbHelper.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final contact in restoredContacts) {
        final baseMap = contact.toMap();
        // We only want to insert the contact row, not relations
        baseMap.remove('interactions');
        baseMap.remove('prayerRequests');
        baseMap.remove('relationships');
        baseMap.remove('tags');
        baseMap['updatedAt'] = nowStr;
        batch.insert(
          'contacts',
          baseMap,
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    // Pass 2: Re-insert full contacts (or specifically interactions)
    // The previous HomePage logic iterated interactions manually.
    // Let's try to leverage DBHelper.insertContact for the full update if possible,
    // OR replicate the manual interaction insertion which gives more control.
    //
    // The HomePage logic manually inserted interactions to ensure participant IDs were valid.
    // Let's stick to the proven manual logic from HomePage for now to minimize regression risk.

    await db.transaction((txn) async {
      for (final contact in restoredContacts) {
        // We need to re-insert the contact's interactions and prayer requests.
        // Calling upsertContactRow inside a single transaction prevents N+1 query overhead.
        await _dbHelper.contactDao.upsertContactRow(txn, contact,
            isUpdate: true, forceNowTimestamps: false);
      }
    });

    // Pass 3: Insert Prayer Lists
    // Wrap prayer lists in a transaction to prevent N+1 queries.
    // While insertPrayerList creates its own transaction, nesting transactions
    // in sqflite is supported (it ignores the nested transaction and uses the parent one).
    if (restoredPrayerLists.isNotEmpty) {
      await db.transaction((txn) async {
        for (final list in restoredPrayerLists) {
          final map = list.toMap();
          map['updatedAt'] = nowStr;
          map['deletedAt'] = null;

          await txn.insert(
            'prayer_lists',
            map,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
          );

          final batch = txn.batch();
          for (final contactId in list.contactIds) {
            batch.insert(
              'prayer_list_members',
              {
                'listId': list.id,
                'contactId': contactId,
              },
              conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
            );
          }
          await batch.commit(noResult: true);
        }
      });
    }

    // Pass 3b: Insert relationships (insertContact does not sync these).
    final relationshipsToInsert = [
      for (final contact in restoredContacts)
        for (final relationship in contact.relationships)
          relationship.copyWith(id: null),
    ];
    if (relationshipsToInsert.isNotEmpty) {
      await _dbHelper.relationshipDao.insertRelationshipsBulk(
        relationshipsToInsert,
      );
    }

    // Pass 4: Refresh reminders
    await _reminderCoordinator.refreshAllContacts();

    return restoredContacts.length;
  }
}
