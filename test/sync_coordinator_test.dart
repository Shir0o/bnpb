import 'dart:convert';
import 'dart:io';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'repositories/mock_db_helper.dart';

class FakeDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  final List<Interaction> interactions = [];
  final List<PrayerRequest> prayerRequests = [];
  final List<PrayerList> prayerLists = [];

  @override
  Future<List<PrayerList>> getPrayerLists() async {
    return List.from(prayerLists);
  }

  @override
  Future<List<PrayerList>> getPrayerListsModifiedSince(DateTime? since) async {
    if (since == null) return List.from(prayerLists);
    return prayerLists.where((l) => l.updatedAt.isAfter(since)).toList();
  }

  @override
  Future<List<Contact>> getContactsModifiedSince(DateTime? since) async {
    if (since == null) return List.from(contacts);
    return contacts.where((c) => c.updatedAt.isAfter(since)).toList();
  }

  @override
  Future<List<Interaction>> getInteractionsModifiedSince(
      DateTime? since) async {
    if (since == null) return List.from(interactions);
    return interactions.where((i) => i.updatedAt.isAfter(since)).toList();
  }

  @override
  Future<List<PrayerRequest>> getPrayerRequestsModifiedSince(
      DateTime? since) async {
    if (since == null) return List.from(prayerRequests);
    return prayerRequests.where((p) => p.updatedAt.isAfter(since)).toList();
  }
}

void main() {
  late Directory tempDir;
  late FakeDBHelper fakeDb;
  late SyncCoordinator coordinator;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test');
    fakeDb = FakeDBHelper();

    SharedPreferences.setMockInitialValues({});
    coordinator = SyncCoordinator(fakeDb);

    // Initialize coordinator (loads device ID)
    // We can't easily wait for init as it's in constructor/async.
    // But exportChanges calls _ensureDeviceId.
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('exportChanges generates JSON file with modified data', () async {
    // Setup data
    final now = DateTime.now().toUtc();
    final contact = Contact(
      id: "c1",
      firstName: "John",
      lastName: "Doe",
      updatedAt: now,
    );
    fakeDb.contacts.add(contact);

    final interaction = Interaction(
      id: 1,
      occurredAt: now,
      summary: "Met",
      medium: "In-person",
      updatedAt: now,
      participantIds: ["c1"],
    );
    fakeDb.interactions.add(interaction);

    // Run export
    await coordinator.exportChanges(tempDir);

    // Verify file created
    final files = await tempDir.list().toList();
    final jsonFiles = files
        .where((f) =>
            f.path.endsWith('.json') &&
            !f.path.endsWith('processed_files.json'))
        .toList();
    expect(jsonFiles.length, 1);

    final file = File(jsonFiles.first.path);
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    expect(json['deviceId'], isNotNull);
    expect(json['contacts'], hasLength(1));
    expect((json['contacts'] as List).first['id'], 'c1');
    expect(json['interactions'], hasLength(1));
    expect((json['interactions'] as List).first['summary'], 'Met');
  });

  test('exportChanges does not export if no changes', () async {
    // First export to set baseline
    await coordinator.exportChanges(tempDir);

    // We need to wait a tiny bit to ensure timestamps differ if we rely on "modifiedSince"
    // However, the test uses fake DB which returns EVERYTHING if since is null (first run).
    // Second run, since is NOT null (set by first run).
    // fakeDb filters by strict > comparison usually? Or >=?
    // The implementation: return items where updatedAt.isAfter(since).
    // Since updatedAt is 'now' from first run, and second run sets 'since' to 'now'.
    // If we run immediately, updatedAt == since, so isAfter is false.
    // So getContactsModifiedSince returns empty list.

    // Clear directory (remove the first export file to verifying no NEW file is created)
    final filesBefore = await tempDir
        .list()
        .where((e) =>
            e.path.endsWith('.json') &&
            !e.path.endsWith('processed_files.json'))
        .toList();
    for (var f in filesBefore) {
      await f.delete();
    }

    // Run export again immediately (no data change)
    await coordinator.exportChanges(tempDir);

    final filesAfter = await tempDir
        .list()
        .where((e) =>
            e.path.endsWith('.json') &&
            !e.path.endsWith('processed_files.json'))
        .toList();
    expect(filesAfter, isEmpty);
  });
}
