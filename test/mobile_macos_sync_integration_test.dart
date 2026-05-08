import 'dart:io';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('mobile and mac sync integration', () {
    late DBHelper dbHelper;
    late Database mobileDb;
    late Database macDb;
    late Directory tempDir;
    late Directory syncDir;
    late _ClientSession mobile;
    late _ClientSession mac;

    setUp(() async {
      dbHelper = DBHelper();
      tempDir = await Directory.systemTemp.createTemp('mobile_macos_sync');
      syncDir = Directory(p.join(tempDir.path, 'shared'));
      await syncDir.create();
      mobileDb = await databaseFactory.openDatabase(
        p.join(tempDir.path, 'mobile.db'),
      );
      macDb = await databaseFactory.openDatabase(
        p.join(tempDir.path, 'mac.db'),
      );
      await dbHelper.createSchemaForTest(mobileDb);
      await dbHelper.createSchemaForTest(macDb);
      mobile = _ClientSession('mobile-client', mobileDb);
      mac = _ClientSession('mac-client', macDb);
    });

    tearDown(() async {
      await mobileDb.close();
      await macDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('syncs both directions through a shared folder within one second',
        () async {
      final mobileCoordinator = SyncCoordinator(dbHelper);
      final macCoordinator = SyncCoordinator(dbHelper);

      await mobile.activate();
      await dbHelper.insertContact(
        Contact(
          id: 'mobile-contact',
          firstName: 'Mobile',
          lastName: 'Friend',
        ),
      );

      final stopwatch = Stopwatch()..start();
      final mobileExport = await mobileCoordinator.exportChanges(syncDir);
      await mobile.savePreferences();

      await mac.activate();
      final macImport = await macCoordinator.importChanges(syncDir);
      final macContactsAfterImport = await dbHelper.getContacts();

      await dbHelper.insertContact(
        Contact(
          id: 'mac-contact',
          firstName: 'Mac',
          lastName: 'Friend',
        ),
      );
      final macExport = await macCoordinator.exportChanges(syncDir);
      await mac.savePreferences();

      await mobile.activate();
      final mobileImport = await mobileCoordinator.importChanges(syncDir);
      final mobileContactsAfterImport = await dbHelper.getContacts();
      stopwatch.stop();

      expect(mobileExport.exportedCount, greaterThanOrEqualTo(1));
      expect(macImport.importedCount, greaterThanOrEqualTo(1));
      expect(macExport.exportedCount, greaterThanOrEqualTo(1));
      expect(mobileImport.importedCount, greaterThanOrEqualTo(1));

      expect(
        macContactsAfterImport.map((contact) => contact.id),
        contains('mobile-contact'),
      );
      expect(
        mobileContactsAfterImport.map((contact) => contact.id),
        containsAll(['mobile-contact', 'mac-contact']),
      );
      expect(
        mobileContactsAfterImport
            .where((contact) => contact.id == 'mobile-contact'),
        hasLength(1),
      );

      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 1)),
        reason:
            'Local handoff should feel nearly instant for a small mobile/mac '
            'delta payload.',
      );
    });
  });
}

class _ClientSession {
  static const _deviceIdKey = 'sync_device_id';
  static const _lastExportKey = 'sync_last_export_time';
  static const _processedFilesKey = 'sync_processed_files';

  final String deviceId;
  final Database database;
  final Map<String, Object> _preferences;

  _ClientSession(this.deviceId, this.database)
      : _preferences = <String, Object>{_deviceIdKey: deviceId};

  Future<void> activate() async {
    DBHelper.setDatabaseForTest(database);
    SharedPreferences.setMockInitialValues(_preferences);
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final lastExport = prefs.getString(_lastExportKey);
    final processedFiles = prefs.getStringList(_processedFilesKey);

    if (lastExport != null) {
      _preferences[_lastExportKey] = lastExport;
    }
    if (processedFiles != null) {
      _preferences[_processedFilesKey] = processedFiles;
    }
  }
}
