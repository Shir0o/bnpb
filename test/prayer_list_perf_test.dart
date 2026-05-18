import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'DBHelper.addContactToPrayerList vs addContactsToPrayerList performance',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      final dbHelper = DBHelper();

      DBHelper.setDatabaseForTest(db);
      await dbHelper.createSchemaForTest(db);

      const listId = 'test-list-id';
      await db.insert('prayer_lists', {
        'id': listId,
        'name': 'Test List',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final int contactCount = 50;
      final contactIds = List.generate(contactCount, (_) => const Uuid().v4());

      debugPrint('Testing baseline (sequential calls to addContactToPrayerList)...');
      final stopwatch = Stopwatch()..start();
      for (final contactId in contactIds) {
        await dbHelper.addContactToPrayerList(listId, contactId);
      }
      stopwatch.stop();
      final baselineMs = stopwatch.elapsedMilliseconds;
      debugPrint('Baseline (N calls): $baselineMs ms');

      await db.delete('prayer_list_members');

      debugPrint('Testing optimized (single call to addContactsToPrayerList)...');
      stopwatch.reset();
      stopwatch.start();
      await dbHelper.addContactsToPrayerList(listId, contactIds);
      stopwatch.stop();
      final optimizedMs = stopwatch.elapsedMilliseconds;
      debugPrint('Optimized (1 call): $optimizedMs ms');

      debugPrint('Improvement: ${((baselineMs - optimizedMs) / baselineMs * 100).toStringAsFixed(2)}%');

      final rows = await db.query('prayer_list_members', where: 'listId = ?', whereArgs: [listId]);
      expect(rows.length, contactCount);

      await db.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
