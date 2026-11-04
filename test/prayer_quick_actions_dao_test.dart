import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DBHelper dbHelper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    dbHelper = DBHelper();
    DBHelper.setDatabaseForTest(db);
    await dbHelper.createSchemaForTest(db);
    for (final id in ['c1', 'c2', 'c3']) {
      await db.insert('contacts', {
        'id': id,
        'firstName': id,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<PrayerRequest> insertRequest({String contactId = 'c1'}) {
    return dbHelper.prayerRequestDao.insertPrayerRequest(
      PrayerRequest(
        participantIds: [contactId],
        description: 'Health',
        status: PrayerRequestStatus.pending,
        requestedAt: DateTime(2026, 10, 1),
      ),
    );
  }

  group('prayed log', () {
    test('togglePrayedToday adds, then tombstones the same day', () async {
      final dao = dbHelper.prayerRequestDao;
      final id = (await insertRequest()).id!;
      final morning = DateTime(2026, 11, 3, 8);

      expect(await dao.togglePrayedToday(id, now: morning), isTrue);
      expect((await dao.getPrayedDates([id]))[id], [morning]);

      expect(
        await dao.togglePrayedToday(id, now: DateTime(2026, 11, 3, 21)),
        isFalse,
      );
      expect(await dao.getPrayedDates([id]), isEmpty);

      final rows = await db.query('prayer_request_prayed_log');
      expect(rows, hasLength(1));
      expect(rows.single['deletedAt'], isNotNull);
    });

    test('getPrayedDates is ascending and counts a day once', () async {
      final dao = dbHelper.prayerRequestDao;
      final a = (await insertRequest()).id!;
      final b = (await insertRequest(contactId: 'c2')).id!;

      await dao.togglePrayedToday(a, now: DateTime(2026, 11, 3, 23, 59));
      await dao.togglePrayedToday(a, now: DateTime(2026, 11, 1, 9));
      await dao.togglePrayedToday(a, now: DateTime(2026, 11, 4, 0, 1));
      // A second device logged Nov 1 too; it arrives through sync.
      await db.insert('prayer_request_prayed_log', {
        'syncId': 'other-device',
        'prayerRequestId': a,
        'prayedAt': DateTime(2026, 11, 1, 18).toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

      final dates = await dao.getPrayedDates([a, b]);
      expect(dates[a], [
        DateTime(2026, 11, 1, 9),
        DateTime(2026, 11, 3, 23, 59),
        DateTime(2026, 11, 4, 0, 1),
      ]);
      expect(dates.containsKey(b), isFalse);

      // Toggling Nov 1 off clears both devices' entries for that day.
      expect(
        await dao.togglePrayedToday(a, now: DateTime(2026, 11, 1, 20)),
        isFalse,
      );
      expect((await dao.getPrayedDates([a]))[a], hasLength(2));
    });

    test('survives a contact save that replaces prayer request rows', () async {
      final dao = dbHelper.prayerRequestDao;
      final request = await insertRequest();
      await dao.togglePrayedToday(request.id!);

      await db.transaction((txn) async {
        await dao.replacePrayerRequestsForContact(
          txn,
          Contact(id: 'c1', firstName: 'c1', prayerRequests: [request]),
        );
      });

      expect(
          (await dao.getPrayedDates([request.id!]))[request.id!], hasLength(1));
    });

    test('sync export rows round-trip through importSyncData', () async {
      final dao = dbHelper.prayerRequestDao;
      final request = await insertRequest();
      final remoteTime = DateTime.utc(2026, 11, 2, 7);
      final entry = {
        'syncId': 'remote-1',
        'prayerRequestSyncId': request.syncId,
        'prayedAt': remoteTime.toIso8601String(),
        'updatedAt': remoteTime.toIso8601String(),
        'deletedAt': null,
      };
      final coordinator = SyncCoordinator(dbHelper);

      await coordinator.importSyncData({
        'prayedLog': [
          entry,
          {...entry, 'syncId': 'orphan', 'prayerRequestSyncId': 'unknown'},
        ],
      });
      expect((await dao.getPrayedDates([request.id!]))[request.id!],
          [remoteTime.toLocal()]);

      final exported = await dao.getPrayedLogForSync(
        updatedSince: remoteTime.subtract(const Duration(minutes: 1)),
      );
      expect(exported.single['syncId'], 'remote-1');
      expect(exported.single['prayerRequestSyncId'], request.syncId);

      final deletedAt = remoteTime.add(const Duration(hours: 1));
      await coordinator.importSyncData({
        'prayedLog': [
          {
            ...entry,
            'updatedAt': deletedAt.toIso8601String(),
            'deletedAt': deletedAt.toIso8601String(),
          },
        ],
      });
      expect(await dao.getPrayedDates([request.id!]), isEmpty);
    });
  });

  group('setStatus', () {
    Future<Map<String, Object?>> row(int id) async =>
        (await db.query('prayer_requests', where: 'id = ?', whereArgs: [id]))
            .single;

    test('answered, archived and reopened', () async {
      final dao = dbHelper.prayerRequestDao;
      final id = (await insertRequest()).id!;
      final before = (await row(id))['updatedAt'] as String;
      final answeredOn = DateTime(2026, 11, 1, 10);
      final archivedOn = DateTime(2026, 11, 3, 10);

      await dao.setStatus(
        id,
        PrayerRequestStatus.answered,
        comment: 'Healed',
        now: answeredOn,
      );
      var r = await row(id);
      expect(r['status'], 'answered');
      expect(r['answeredAt'], answeredOn.toIso8601String());
      expect(r['reflectionNotes'], 'Healed');
      expect(
        DateTime.parse(r['updatedAt'] as String)
            .isBefore(DateTime.parse(before)),
        isFalse,
      );

      await dao.setStatus(id, PrayerRequestStatus.archived, now: archivedOn);
      r = await row(id);
      expect(r['status'], 'archived');
      expect(r['archivedAt'], archivedOn.toIso8601String());
      expect(r['reflectionNotes'], 'Healed');

      final archived = (await dao.getPrayerRequests()).single;
      expect(archived.archivedAt, archivedOn);

      await dao.setStatus(
        id,
        PrayerRequestStatus.archived,
        comment: 'No longer relevant',
        now: archivedOn,
      );
      expect((await row(id))['reflectionNotes'], 'No longer relevant');

      await dao.setStatus(id, PrayerRequestStatus.pending);
      r = await row(id);
      expect(r['status'], 'pending');
      expect(r['answeredAt'], isNull);
      expect(r['archivedAt'], isNull);
      expect(r['reflectionNotes'], isNull);
    });
  });

  test('createForEachContact inserts one request per contact', () async {
    final dao = dbHelper.prayerRequestDao;
    final template = PrayerRequest(
      participantIds: const [],
      description: 'Exams',
      status: PrayerRequestStatus.pending,
      requestedAt: DateTime(2026, 11, 3),
      category: 'School',
    );

    final ids = await dao.createForEachContact(template, ['c1', 'c2']);
    expect(ids, hasLength(2));

    final requests = await dao.getPrayerRequests();
    expect(requests.map((r) => r.syncId).toSet(), hasLength(2));
    expect(requests.map((r) => r.syncId), isNot(contains(template.syncId)));
    for (final (i, contactId) in ['c1', 'c2'].indexed) {
      final request = requests.singleWhere((r) => r.id == ids[i]);
      expect(request.participantIds, [contactId]);
      expect(request.contactId, contactId);
      expect(request.description, 'Exams');
      expect(request.category, 'School');
    }
  });

  group('merged prayer list', () {
    test('union, add to default list, and remove everywhere', () async {
      final dao = dbHelper.prayerListDao;
      await dao.insertPrayerList(
        PrayerList(id: 'l1', name: 'Family', contactIds: ['c1', 'c2']),
      );
      await dao.insertPrayerList(
        PrayerList(id: 'l2', name: 'Church', contactIds: ['c2']),
      );
      await dao.insertPrayerList(
        PrayerList(id: 'l3', name: 'Old', contactIds: ['c3']),
      );
      await dao.deletePrayerList('l3');

      expect(
        await dao.getAllPrayerListContactIds(),
        unorderedEquals(['c1', 'c2']),
      );

      await dao.addContactsToDefaultList(['c1', 'c3']);
      final defaultList = await dao.getPrayerList(PrayerList.defaultListId);
      expect(defaultList!.contactIds, ['c3']);
      expect(
        await dao.getAllPrayerListContactIds(),
        unorderedEquals(['c1', 'c2', 'c3']),
      );

      await dao.removeContactFromAllLists('c2');
      expect(
        await dao.getAllPrayerListContactIds(),
        unorderedEquals(['c1', 'c3']),
      );
      expect((await dao.getPrayerList('l1'))!.contactIds, ['c1']);
      expect((await dao.getPrayerList('l2'))!.contactIds, isEmpty);
    });

    test('getAllPrayerListContactIds skips deleted contacts', () async {
      final dao = dbHelper.prayerListDao;
      await dao.addContactsToDefaultList(['c1', 'c2']);
      await dbHelper.contactDao.deleteContact('c2');

      expect(await dao.getAllPrayerListContactIds(), ['c1']);
    });
  });
}
