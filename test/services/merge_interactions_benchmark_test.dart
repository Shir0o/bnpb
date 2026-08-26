import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Merge Interactions Performance & Correctness', () {
    late Database db;
    late DBHelper dbHelper;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      dbHelper = DBHelper();
      DBHelper.setDatabaseForTest(db);
      await dbHelper.createSchemaForTest(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Measures time to merge 200 interactions', () async {
      // 1. Insert 50 contacts
      final contacts = List.generate(
        50,
        (i) => Contact(id: 'c_$i', firstName: 'Contact $i'),
      );
      for (final c in contacts) {
        await dbHelper.insertContact(c);
      }

      // 2. Generate 200 interactions to merge
      final remoteInteractions = List.generate(
        200,
        (i) => Interaction(
          syncId: 'sync_int_$i',
          occurredAt: DateTime.now().toUtc(),
          summary: 'Interaction $i',
          medium: 'Phone',
          participantIds: ['c_${i % 50}', 'c_${(i + 1) % 50}'],
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final payload = {
        'version': 2,
        'deviceId': 'remote-device',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'integrityCheck': 'valid',
        'interactions': remoteInteractions.map((i) => i.toMap(includeId: false)).toList(),
      };

      final coordinator = SyncCoordinator(dbHelper);

      final stopwatch = Stopwatch()..start();
      await coordinator.importSyncData(payload);
      stopwatch.stop();

      debugPrint('Merge 200 interactions execution time: ${stopwatch.elapsedMilliseconds}ms');

      final imported = await dbHelper.getInteractions(includeDeleted: true);
      expect(imported, hasLength(200));

      // Benchmark on updated data
      final updatedInteractions = remoteInteractions.map((i) {
        final map = i.toMap(includeId: false);
        map['summary'] = '${i.summary} updated';
        map['updatedAt'] = DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String();
        return map;
      }).toList();

      final updatePayload = {
        'version': 2,
        'deviceId': 'remote-device',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'integrityCheck': 'valid',
        'interactions': updatedInteractions,
      };

      final updateStopwatch = Stopwatch()..start();
      await coordinator.importSyncData(updatePayload);
      updateStopwatch.stop();

      debugPrint('Merge update 200 interactions execution time: ${updateStopwatch.elapsedMilliseconds}ms');

      final updatedImported = await dbHelper.getInteractions(includeDeleted: true);
      expect(updatedImported, hasLength(200));
      expect(updatedImported.first.summary, contains('updated'));
    });
  });
}
