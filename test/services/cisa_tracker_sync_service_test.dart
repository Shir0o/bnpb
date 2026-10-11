import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/cisa_tracker_sync_service.dart';

import '../repositories/mock_db_helper.dart';

class FakeDBHelperForCisa extends MockDBHelper {
  final List<Interaction> interactions = [];
  final Map<String, Contact> contactsById = {};

  @override
  Future<List<Interaction>> getInteractions({
    DateTime? start,
    DateTime? end,
    String? contactId,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return interactions.where((i) {
      if (!includeDeleted && i.deletedAt != null) return false;
      if (updatedSince != null && !i.updatedAt.isAfter(updatedSince)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return contactsById.values.toList();
  }
}

typedef _SetenvC = Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32);
typedef _SetenvD = int Function(Pointer<Uint8>, Pointer<Uint8>, int);
typedef _MallocC = Pointer<Uint8> Function(IntPtr);
typedef _MallocD = Pointer<Uint8> Function(int);

/// Switches this test process's local time zone (setenv + tzset), so the
/// timezone tests bite on a UTC CI runner too. Each test file runs in its own
/// process, so this does not leak into other files.
void _setProcessTimeZone(String tz) {
  final libc = DynamicLibrary.process();
  final malloc = libc.lookupFunction<_MallocC, _MallocD>('malloc');
  Pointer<Uint8> cString(String s) {
    final units = utf8.encode(s);
    final p = malloc(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    return p;
  }

  libc.lookupFunction<_SetenvC, _SetenvD>('setenv')(
      cString('TZ'), cString(tz), 1);
  libc.lookupFunction<Void Function(), void Function()>('tzset')();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDBHelperForCisa fakeDb;
  late CisaTrackerSyncService service;
  late List<http.Request> capturedRequests;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    fakeDb = FakeDBHelperForCisa();
    capturedRequests = [];
  });

  CisaTrackerSyncService makeService({
    int statusCode = 200,
    String responseBody = '{"success":true}',
    http.Client? customClient,
  }) {
    final client = customClient ??
        MockClient((request) async {
          capturedRequests.add(request);
          return http.Response(responseBody, statusCode);
        });
    return CisaTrackerSyncService(
      dbHelper: fakeDb,
      httpClient: client,
    );
  }

  group('CisaTrackerSyncService Token Management', () {
    test('readToken returns null when not set', () async {
      service = makeService();
      expect(await service.getToken(), isNull);
      expect(await service.hasToken(), isFalse);
    });

    test('saveToken persists token and hasToken returns true', () async {
      service = makeService();
      await service.setToken('test-secret-token');
      expect(await service.getToken(), 'test-secret-token');
      expect(await service.hasToken(), isTrue);
    });

    test('clearToken removes token', () async {
      service = makeService();
      await service.setToken('test-secret-token');
      await service.clearToken();
      expect(await service.getToken(), isNull);
      expect(await service.hasToken(), isFalse);
    });
  });

  group('CisaTrackerSyncService Push Logic', () {
    test('does nothing if no token is set', () async {
      service = makeService();
      final result = await service.pushInteractions();
      expect(result.status, CisaSyncStatus.noToken);
      expect(capturedRequests, isEmpty);
    });

    test('first push includes all interactions and formats contract correctly',
        () async {
      service = makeService();
      await service.setToken('secret-123');

      fakeDb.contactsById['c1'] = Contact(
        id: 'c1',
        firstName: 'Alex',
        lastName: 'Chen',
        nickname: 'Al',
      );
      fakeDb.contactsById['c2'] = Contact(
        id: 'c2',
        firstName: 'Beth',
        lastName: 'Doe',
      );

      final occurred = DateTime.utc(2026, 9, 10, 15, 0);
      final updated = DateTime.utc(2026, 9, 10, 15, 30);

      fakeDb.interactions.add(
        Interaction(
          id: 1,
          syncId: 'sync-1',
          occurredAt: occurred,
          durationMinutes: 45,
          summary: 'Coffee downtown',
          medium: 'coffee',
          notes: 'private notes should not be sent',
          location: 'Secret cafe',
          markForPrayer: true,
          followUpAt: DateTime.utc(2026, 9, 15),
          updatedAt: updated,
          participantIds: ['c1', 'c2'],
        ),
      );

      final result = await service.pushInteractions();
      expect(result.status, CisaSyncStatus.success);
      expect(result.pushedCount, 1);
      expect(capturedRequests.length, 1);

      final req = capturedRequests.first;
      expect(req.url.path, '/api/bnpb/sync');
      expect(req.headers['x-sync-token'], 'secret-123');
      expect(req.headers['content-type'], contains('application/json'));

      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final interactions = body['interactions'] as List;
      expect(interactions.length, 1);

      final item = interactions.first as Map<String, dynamic>;
      expect(item['syncId'], 'sync-1');
      expect(item['occurredAt'], occurred.toIso8601String());
      expect(item['durationMinutes'], 45);
      expect(item['summary'], 'Coffee downtown');
      expect(item['medium'], 'coffee');
      expect(item['updatedAt'], updated.toIso8601String());
      expect(item['deleted'], isFalse);

      // Verify private fields are NEVER sent
      expect(item.containsKey('notes'), isFalse);
      expect(item.containsKey('location'), isFalse);
      expect(item.containsKey('markForPrayer'), isFalse);
      expect(item.containsKey('followUpAt'), isFalse);
      expect(item.containsKey('attachments'), isFalse);

      // Verify participants
      final participants = item['participants'] as List;
      expect(participants.length, 2);
      expect(participants[0], {
        'bnpbContactId': 'c1',
        'firstName': 'Alex',
        'lastName': 'Chen',
        'nickname': 'Al',
      });
      expect(participants[1], {
        'bnpbContactId': 'c2',
        'firstName': 'Beth',
        'lastName': 'Doe',
      });

      // Verify cursor is updated to the newest updatedAt
      final cursor = await service.getLastPushCursor();
      expect(cursor, updated);
      expect(await service.getLastPushSuccess(), isNotNull);
      expect(await service.getLastPushError(), isNull);
    });

    test('later pushes only include interactions updated after cursor',
        () async {
      service = makeService();
      await service.setToken('secret-123');

      final time1 = DateTime.utc(2026, 9, 10, 10, 0);
      final time2 = DateTime.utc(2026, 9, 10, 12, 0);

      fakeDb.interactions.add(
        Interaction(
          syncId: 'sync-1',
          occurredAt: time1,
          summary: 'First',
          medium: 'call',
          updatedAt: time1,
        ),
      );

      // First push
      await service.pushInteractions();
      expect(capturedRequests.length, 1);
      capturedRequests.clear();

      // Add second interaction later
      fakeDb.interactions.add(
        Interaction(
          syncId: 'sync-2',
          occurredAt: time2,
          summary: 'Second',
          medium: 'chat',
          updatedAt: time2,
        ),
      );

      final result2 = await service.pushInteractions();
      expect(result2.status, CisaSyncStatus.success);
      expect(result2.pushedCount, 1);
      expect(capturedRequests.length, 1);

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      final interactions = body['interactions'] as List;
      expect(interactions.length, 1);
      expect(interactions.first['syncId'], 'sync-2');
      expect(await service.getLastPushCursor(), time2);
    });

    test('sends deleted interactions with deleted=true tombstone', () async {
      service = makeService();
      await service.setToken('secret-123');

      final time = DateTime.utc(2026, 9, 10, 10, 0);
      fakeDb.interactions.add(
        Interaction(
          syncId: 'sync-deleted',
          occurredAt: time,
          summary: 'Deleted meeting',
          medium: 'meeting',
          updatedAt: time,
          deletedAt: time,
        ),
      );

      final result = await service.pushInteractions();
      expect(result.status, CisaSyncStatus.success);
      expect(capturedRequests.length, 1);

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      final interactions = body['interactions'] as List;
      expect(interactions.first['deleted'], isTrue);
    });

    test('pages pushes when exceeding per-request cap of 200', () async {
      service = makeService();
      await service.setToken('secret-123');

      final baseTime = DateTime.utc(2026, 9, 10, 10, 0);
      for (int i = 0; i < 250; i++) {
        fakeDb.interactions.add(
          Interaction(
            syncId: 'sync-$i',
            occurredAt: baseTime.add(Duration(minutes: i)),
            summary: 'Meeting $i',
            medium: 'call',
            updatedAt: baseTime.add(Duration(minutes: i)),
          ),
        );
      }

      final result = await service.pushInteractions();
      expect(result.status, CisaSyncStatus.success);
      expect(result.pushedCount, 250);
      expect(capturedRequests.length, 2);

      final page1 =
          jsonDecode(capturedRequests[0].body)['interactions'] as List;
      final page2 =
          jsonDecode(capturedRequests[1].body)['interactions'] as List;
      expect(page1.length, 200);
      expect(page2.length, 50);

      expect(await service.getLastPushCursor(),
          baseTime.add(const Duration(minutes: 249)));
    });

    test(
        'handles 401 unauthorized: records auth error and does not advance cursor',
        () async {
      service = makeService(
        statusCode: 401,
        responseBody: '{"success":false,"error":"Invalid or revoked token."}',
      );
      await service.setToken('secret-bad');

      final time = DateTime.utc(2026, 9, 10, 10, 0);
      fakeDb.interactions.add(
        Interaction(
          syncId: 'sync-1',
          occurredAt: time,
          summary: 'Call',
          medium: 'call',
          updatedAt: time,
        ),
      );

      final result = await service.pushInteractions();
      expect(result.status, CisaSyncStatus.unauthorized);
      expect(await service.getLastPushCursor(), isNull);
      expect(await service.getLastPushError(),
          contains('Invalid or revoked token'));
    });

    test('does not advance cursor on failure and retries on next push',
        () async {
      var callCount = 0;
      final client = MockClient((request) async {
        capturedRequests.add(request);
        callCount++;
        if (callCount == 1) {
          return http.Response('{"error":"Server error"}', 500);
        }
        return http.Response('{"success":true}', 200);
      });

      service = makeService(customClient: client);
      await service.setToken('secret-123');

      final time = DateTime.utc(2026, 9, 10, 10, 0);
      fakeDb.interactions.add(
        Interaction(
          syncId: 'sync-1',
          occurredAt: time,
          summary: 'Call',
          medium: 'call',
          updatedAt: time,
        ),
      );

      // Attempt 1 -> fails
      final result1 = await service.pushInteractions();
      expect(result1.status, CisaSyncStatus.error);
      expect(await service.getLastPushCursor(), isNull);
      expect(await service.getLastPushError(), isNotNull);

      // Attempt 2 -> succeeds
      final result2 = await service.pushInteractions();
      expect(result2.status, CisaSyncStatus.success);
      expect(await service.getLastPushCursor(), time);
      expect(await service.getLastPushError(), isNull);
    });
  });
  group('against the real interactions query (non-UTC time zone)', () {
    late Database db;
    late DBHelper realDb;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _setProcessTimeZone('America/Los_Angeles');
    });

    tearDownAll(() {
      _setProcessTimeZone(Platform.environment['TZ'] ?? 'UTC');
    });

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      realDb = DBHelper();
      DBHelper.setDatabaseForTest(db);
      await realDb.createSchemaForTest(db);
      await db.insert('contacts', {
        'id': 'c1',
        'firstName': 'Alex',
        'updatedAt': '2026-10-01T00:00:00.000Z',
      });
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertRow(String syncId, String updatedAt,
        {String? deletedAt}) async {
      final id = await db.insert('interactions', {
        'syncId': syncId,
        'occurredAt': '2026-10-11T08:00:00.000',
        'summary': 'Talk $syncId',
        'medium': 'call',
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
      });
      await db.insert('interaction_participants', {
        'interactionId': id,
        'contactId': 'c1',
      });
    }

    List<String> pushedSyncIds(http.Request request) =>
        ((jsonDecode(request.body) as Map)['interactions'] as List)
            .map((i) => (i as Map)['syncId'] as String)
            .toList();

    test('runs in a time zone behind UTC', () {
      expect(DateTime(2026, 10, 11).timeZoneOffset, const Duration(hours: -7));
    });

    test('getInteractions(updatedSince) compares instants, not stored text',
        () async {
      // Cursor: 15:55 UTC == 08:55 Pacific.
      final cursor = DateTime.utc(2026, 10, 11, 15, 55);
      await insertRow('before-utc', '2026-10-11T15:54:59.000Z');
      await insertRow('before-local', '2026-10-11T08:54:59.000');
      // Three hours after the cursor, stored as offsetless local time (the
      // shape pre-Feb-2026 builds and Drive-merged rows can carry). As text
      // it reads "11:55" < "15:55Z", so a text comparison drops it.
      await insertRow('after-local', '2026-10-11T11:55:00.000');
      await insertRow('after-utc', '2026-10-11T18:55:00.000Z');
      // Same millisecond as the cursor, but later microseconds.
      await insertRow('after-micro', '2026-10-11T15:55:00.000500Z');

      final found = await realDb.getInteractions(
        updatedSince: cursor,
        includeDeleted: true,
      );
      expect(found.map((i) => i.syncId).toSet(),
          {'after-local', 'after-utc', 'after-micro'});
    });

    test('a local-time edit a few hours after the cursor is pushed next time',
        () async {
      SharedPreferences.setMockInitialValues({});
      final requests = <http.Request>[];
      final service = CisaTrackerSyncService(
        dbHelper: realDb,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"success":true}', 200);
        }),
      );
      await service.setToken('secret-123');

      await insertRow('first', '2026-10-11T15:55:00.123Z');
      expect((await service.pushInteractions()).pushedCount, 1);

      // Edited 3 hours later, stored as local wall-clock time.
      await insertRow('edited-later', '2026-10-11T11:55:00.000');
      final result = await service.pushInteractions();

      expect(result.status, CisaSyncStatus.success);
      expect(requests.length, 2);
      expect(pushedSyncIds(requests.last), ['edited-later']);
    });

    test('a cursor saved by an earlier build is ignored once: full re-send',
        () async {
      SharedPreferences.setMockInitialValues({
        // Written by the buggy build; may have skipped edits after it.
        'cisa_tracker_last_push_cursor': '2026-10-11T15:55:00.123Z',
      });
      final requests = <http.Request>[];
      final service = CisaTrackerSyncService(
        dbHelper: realDb,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"success":true}', 200);
        }),
      );
      await service.setToken('secret-123');

      await insertRow('pushed-before', '2026-10-11T15:55:00.123Z');
      await insertRow('skipped-by-bug', '2026-10-11T11:55:00.000');
      await insertRow('deleted-in-gap', '2026-10-11T12:00:00.000',
          deletedAt: '2026-10-11T12:00:00.000');

      final result = await service.pushInteractions();
      expect(result.status, CisaSyncStatus.success);
      expect(pushedSyncIds(requests.single).toSet(),
          {'pushed-before', 'skipped-by-bug', 'deleted-in-gap'});

      // The next push starts from the new cursor, not the legacy one.
      requests.clear();
      final again = await service.pushInteractions();
      expect(again.pushedCount, 0);
      expect(requests, isEmpty);
    });
  });
}
