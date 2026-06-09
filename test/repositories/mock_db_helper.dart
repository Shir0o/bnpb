import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:bnpb/db/db_helper.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/notification_preference.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/models/prayer_list.dart';

import 'package:bnpb/db/daos/contact_dao.dart';
import 'package:bnpb/db/daos/interaction_dao.dart';
import 'package:bnpb/db/daos/prayer_request_dao.dart';
import 'package:bnpb/db/daos/relationship_dao.dart';
import 'package:bnpb/db/daos/prayer_list_dao.dart';

class MockDBHelper implements DBHelper {
  @override
  ContactDao get contactDao => throw UnimplementedError();
  @override
  InteractionDao get interactionDao => throw UnimplementedError();
  @override
  PrayerRequestDao get prayerRequestDao => throw UnimplementedError();
  @override
  RelationshipDao get relationshipDao => throw UnimplementedError();
  @override
  PrayerListDao get prayerListDao => throw UnimplementedError();

  @override
  Future<Database> get database => throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<void> createSchemaForTest(Database db) async {}

  @override
  Future<void> insertContact(Contact contact) => throw UnimplementedError();

  @override
  Future<void> upsertContactFromSync(
    DatabaseExecutor txn,
    Contact contact, {
    required bool isUpdate,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> upsertContactRowForTest(
    DatabaseExecutor txn,
    Contact contact, {
    required bool isUpdate,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Contact>> getContactsModifiedSince(DateTime? since) =>
      throw UnimplementedError();

  @override
  Future<Contact?> getContactById(String id) async => null;

  @override
  Future<NotificationPreference> upsertNotificationPreference(
    NotificationPreference preference,
  ) =>
      throw UnimplementedError();

  @override
  Future<NotificationPreference?> getNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<NotificationPreference>> getNotificationPreferences({
    NotificationScopeType? scopeType,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> deleteContact(String id) => throw UnimplementedError();

  @override
  Future<void> deleteInteraction(int id) => throw UnimplementedError();

  @override
  Future<void> deletePrayerRequest(int id) => throw UnimplementedError();

  @override
  Future<void> deleteRelationship(int id) => throw UnimplementedError();

  @override
  Future<List<Relationship>> getAllRelationships() async => [];

  @override
  Future<List<String>> getDistinctLocations() async => [];

  @override
  Future<Interaction?> getInteractionById(int interactionId) =>
      throw UnimplementedError();

  @override
  Future<List<Interaction>> getInteractions({
    DateTime? start,
    DateTime? end,
    String? contactId,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Interaction>> getInteractionsModifiedSince(DateTime? since) =>
      throw UnimplementedError();

  @override
  Future<List<Interaction>> getInteractionsForContact(String contactId) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getPrayerCategories() => throw UnimplementedError();

  @override
  Future<List<Interaction>> getPrayerFocusInteractions({int limit = 10}) =>
      throw UnimplementedError();

  @override
  Future<Map<PrayerRequestStatus, int>> getPrayerRequestCounts() =>
      throw UnimplementedError();

  @override
  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PrayerRequest>> getPrayerRequestsModifiedSince(DateTime? since) =>
      throw UnimplementedError();

  @override
  Future<List<PrayerRequest>> getPrayerRequestsForContact(String contactId) =>
      throw UnimplementedError();

  @override
  Future<List<Relationship>> getRelationshipsForContact(String contactId) =>
      throw UnimplementedError();

  @override
  Future<Interaction> insertInteraction(Interaction interaction) =>
      throw UnimplementedError();

  @override
  Future<PrayerRequest> insertPrayerRequest(PrayerRequest request) =>
      throw UnimplementedError();

  @override
  Future<bool> interactionExists({
    required String contactId,
    required DateTime occurredAt,
    required String summary,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateContact(Contact contact) => throw UnimplementedError();

  @override
  Future<void> updateInteraction(Interaction interaction) =>
      throw UnimplementedError();

  @override
  Future<void> updatePrayerRequest(PrayerRequest request) =>
      throw UnimplementedError();

  @override
  Future<Relationship> upsertRelationship(Relationship relationship) =>
      throw UnimplementedError();

  @override
  Future<List<PrayerList>> getPrayerLists() async => [];
  @override
  Future<List<PrayerList>> getPrayerListsModifiedSince(DateTime? since) =>
      throw UnimplementedError();

  @override
  Future<PrayerList?> getPrayerList(String id) => throw UnimplementedError();

  @override
  Future<void> insertPrayerList(PrayerList list) => throw UnimplementedError();

  @override
  Future<void> updatePrayerList(PrayerList list) => throw UnimplementedError();

  @override
  Future<void> deletePrayerList(String id) => throw UnimplementedError();

  @override
  Future<void> addContactToPrayerList(String listId, String contactId) =>
      throw UnimplementedError();

  @override
  Future<void> removeContactFromPrayerList(String listId, String contactId) =>
      throw UnimplementedError();

  @override
  Future<void> replaceInteractionParticipants(
    DatabaseExecutor db,
    int id,
    List<String> participants,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> replacePrayerRequestParticipants(
    DatabaseExecutor db,
    int id,
    List<String> participants,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> upsertPrayerListFromSync(DatabaseExecutor db, PrayerList list) =>
      throw UnimplementedError();

  @override
  Future<int> deDuplicateInteractions() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> getGlobalMetadata() async {
    return {
      'contactCount': 0,
      'interactionCount': 0,
      'prayerCount': 0,
      'lastUpdate': null,
    };
  }

  @override
  Future<void> clearAllData() async {}
}
