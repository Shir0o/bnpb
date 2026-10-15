import 'dart:io';

import 'package:bnpb/db/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/process_time_zone.dart';

// Stored updatedAt strings are mixed: UTC with "Z", offsetless local time, and
// SQLite's "YYYY-MM-DD HH:MM:SS" column default. The updatedSince cursor must
// compare instants, not text (#313).
void main() {
  late Database db;
  late DBHelper dbHelper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setProcessTimeZone('America/Los_Angeles');
  });

  tearDownAll(() {
    setProcessTimeZone(Platform.environment['TZ'] ?? 'UTC');
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    dbHelper = DBHelper();
    DBHelper.setDatabaseForTest(db);
    await dbHelper.createSchemaForTest(db);
    await db.insert('contacts', {
      'id': 'owner',
      'firstName': 'Owner',
      'updatedAt': '2000-01-01T00:00:00.000Z',
    });
  });

  tearDown(() async {
    await db.close();
  });

  // Cursor: 15:55 UTC == 08:55 Pacific (UTC-7).
  final cursor = DateTime.utc(2026, 10, 11, 15, 55);

  // Rows that must be returned: later than the cursor, in every stored shape.
  const afterRows = {
    'after-local': '2026-10-11T11:55:00.000', // offsetless local, 3h later
    'after-utc': '2026-10-11T18:55:00.000Z',
    'after-sqlite': '2026-10-11 20:00:00', // later whether read as UTC or local
    'after-micro': '2026-10-11T15:55:00.000500Z', // same millisecond as cursor
  };

  // Rows that must not be returned: at or before the cursor.
  const beforeRows = {
    'before-local': '2026-10-11T08:54:59.000',
    'before-utc': '2026-10-11T15:54:59.000Z',
    'before-sqlite': '2026-10-11 08:00:00',
    'at-cursor': '2026-10-11T15:55:00.000Z',
    'before-prior-day': '2026-10-10T23:00:00.000Z',
  };

  test('runs in a time zone behind UTC', () {
    expect(DateTime(2026, 10, 11).timeZoneOffset, const Duration(hours: -7));
  });

  group('ContactDao.getContacts(updatedSince)', () {
    Future<void> insertContacts(Map<String, String> rows) async {
      for (final e in rows.entries) {
        await db.insert('contacts', {
          'id': e.key,
          'firstName': e.key,
          'updatedAt': e.value,
        });
      }
    }

    test('returns only rows later than the cursor, whatever the text format',
        () async {
      await insertContacts({...afterRows, ...beforeRows});

      final found = await dbHelper.getContactsModifiedSince(cursor);

      expect(found.map((c) => c.id).toSet(), afterRows.keys.toSet());
    });

    test('includes soft-deleted rows later than the cursor', () async {
      await insertContacts({'after-local': afterRows['after-local']!});
      await db.update('contacts', {'deletedAt': '2026-10-11T12:00:00.000'},
          where: 'id = ?', whereArgs: ['after-local']);

      final found = await dbHelper.getContactsModifiedSince(cursor);

      expect(found.map((c) => c.id), ['after-local']);
    });

    test('a null cursor still returns every row', () async {
      await insertContacts({...afterRows, ...beforeRows});

      final found = await dbHelper.getContactsModifiedSince(null);

      expect(found.length, afterRows.length + beforeRows.length + 1);
    });
  });

  group('PrayerRequestDao.getPrayerRequests(updatedSince)', () {
    Future<void> insertRequests(Map<String, String> rows,
        {String requestedAt = '2026-10-01T00:00:00.000'}) async {
      for (final e in rows.entries) {
        await db.insert('prayer_requests', {
          'syncId': e.key,
          'contactId': 'owner',
          'description': e.key,
          'status': 'pending',
          'requestedAt': requestedAt,
          'updatedAt': e.value,
        });
      }
    }

    test('returns only rows later than the cursor, whatever the text format',
        () async {
      await insertRequests({...afterRows, ...beforeRows});

      final found = await dbHelper.getPrayerRequestsModifiedSince(cursor);

      expect(found.map((r) => r.syncId).toSet(), afterRows.keys.toSet());
    });

    test('includes soft-deleted rows later than the cursor', () async {
      await insertRequests({'after-local': afterRows['after-local']!});
      await db.update(
          'prayer_requests', {'deletedAt': '2026-10-11T12:00:00.000'},
          where: 'syncId = ?', whereArgs: ['after-local']);

      final found = await dbHelper.getPrayerRequestsModifiedSince(cursor);

      expect(found.map((r) => r.syncId), ['after-local']);
    });

    test('a null cursor still returns every row', () async {
      await insertRequests({...afterRows, ...beforeRows});

      final found = await dbHelper.getPrayerRequestsModifiedSince(null);

      expect(found.length, afterRows.length + beforeRows.length);
    });

    test('limit counts only rows that pass the exact cursor cut', () async {
      // Stale rows sort first (newer requestedAt) and pass a coarse same-day
      // SQL filter, so a LIMIT applied in SQL would hand back only stale rows.
      await insertRequests({
        'stale-1': '2026-10-11T15:00:00.000Z',
        'stale-2': '2026-10-11T08:00:00.000',
      }, requestedAt: '2026-10-10T00:00:00.000');
      await insertRequests({'fresh': '2026-10-11T18:55:00.000Z'});

      final found = await dbHelper.getPrayerRequests(
        updatedSince: cursor,
        limit: 1,
      );

      expect(found.map((r) => r.syncId), ['fresh']);
    });
  });
}
