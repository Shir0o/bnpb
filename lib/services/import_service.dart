import 'dart:convert';
import 'dart:io';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_list.dart';
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
      final groups =
          ImportDuplicateDetector().findDuplicateGroups(restoredContacts);
      if (groups.isNotEmpty) {
        final resolved = await onDuplicatesFound(restoredContacts, groups);
        if (resolved == null) return -1;
        restoredContacts = resolved;
        if (restoredContacts.isEmpty) return 0;
      }
    }

    // Overwrite behavior: clear existing data before importing.
    await _dbHelper.clearAllData();

    // Pass 1: Insert all contacts first (without interactions/requests to avoid FK issues)
    // This ensures all contact IDs exist before we try to link interactions.
    for (final contact in restoredContacts) {
      // Create a version without sub-items for the initial insert
      // Note: insertContact in DBHelper actually handles the sub-items update internally
      // if we pass the full object. However, to be safe with circular/peer references
      // in interaction participants, it might be safer to insert contacts first.
      // But DBHelper.insertContact `_upsertContactRow` does the whole tree for that contact.
      //
      // The issue is if Contact A references Contact B in an interaction, and B hasn't been inserted.
      // SQLite FK constraints might fail if WE force them.
      // The current DBHelper logic inserts the contact row first, THEN interactions.
      // So as long as we iterate TWICE (once for contact rows, once for relations), we are safer.
      //
      // Existing logic in HomePage did:
      // 1. Insert contact (with empty interactions)
      // 2. Insert interactions
      // 3. Insert prayer lists

      final contactWithoutRelations = contact.copyWith(
        interactions: [],
        prayerRequests: [], // Logic in HomePage didn't explicitly clear requests, but stripping interactions is key
      );
      await _dbHelper.insertContact(contactWithoutRelations);
    }

    // Pass 2: Re-insert full contacts (or specifically interactions)
    // The previous HomePage logic iterated interactions manually.
    // Let's try to leverage DBHelper.insertContact for the full update if possible,
    // OR replicate the manual interaction insertion which gives more control.
    //
    // The HomePage logic manually inserted interactions to ensure participant IDs were valid.
    // Let's stick to the proven manual logic from HomePage for now to minimize regression risk.

    for (final contact in restoredContacts) {
      // We need to re-insert the contact's interactions and prayer requests.
      // DBHelper.insertContact does this if we call it with the full object!
      // Calling insertContact again will update the contact and replace relations.
      // This is cleaner than manually looping interactions.
      await _dbHelper.insertContact(contact);
    }

    // Pass 3: Insert Prayer Lists
    for (final list in restoredPrayerLists) {
      await _dbHelper.insertPrayerList(list);
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
