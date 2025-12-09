import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/notification_preference.dart';
import 'package:bnpb/repositories/notification_preferences_repository.dart';
import 'mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  List<NotificationPreference> prefs = [];
  int _idCounter = 1;

  @override
  Future<NotificationPreference?> getNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    try {
      return prefs.firstWhere(
        (p) =>
            p.scopeType == scopeType &&
            p.scopeId == scopeId &&
            p.channel == channel,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NotificationPreference> upsertNotificationPreference(
    NotificationPreference preference,
  ) async {
    final index = prefs.indexWhere(
      (p) =>
          p.scopeType == preference.scopeType &&
          p.scopeId == preference.scopeId &&
          p.channel == preference.channel,
    );
    
    final newPref = preference.id == null
        ? preference.copyWith(id: _idCounter++)
        : preference;

    if (index >= 0) {
      prefs[index] = newPref;
    } else {
      prefs.add(newPref);
    }
    return newPref;
  }

  @override
  Future<void> deleteNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    prefs.removeWhere(
      (p) =>
          p.scopeType == scopeType &&
          p.scopeId == scopeId &&
          p.channel == channel,
    );
  }

  @override
  Future<List<NotificationPreference>> getNotificationPreferences({
    NotificationScopeType? scopeType,
  }) async {
    if (scopeType != null) {
      return prefs.where((p) => p.scopeType == scopeType).toList();
    }
    return prefs;
  }
}

void main() {
  group('NotificationPreferencesRepository', () {
    late NotificationPreferencesRepository repository;
    late _TestDBHelper dbHelper;

    setUp(() {
      dbHelper = _TestDBHelper();
      repository = NotificationPreferencesRepository(dbHelper: dbHelper);
    });

    test('ensureDefaults creates missing global preferences', () async {
      await repository.ensureDefaults();
      // Should have one for each channel
      expect(dbHelper.prefs.length, ReminderChannel.values.length);
      
      // Setup should be idempotent
      await repository.ensureDefaults();
      expect(dbHelper.prefs.length, ReminderChannel.values.length);
    });

    test('resolve uses hierarchy correctly', () async {
      // 1. Global only
      await repository.savePreference(
        const NotificationPreference(
          scopeType: NotificationScopeType.global,
          scopeId: 'global',
          channel: ReminderChannel.followUp,
          enabled: true,
          leadTime: Duration(hours: 1),
        ),
      );
      var resolved = await repository.resolve(
        channel: ReminderChannel.followUp,
        contactId: 'c1',
        category: 'Work',
      );
      expect(resolved.leadTime, const Duration(hours: 1));

      // 2. Category override
      await repository.savePreference(
        const NotificationPreference(
          scopeType: NotificationScopeType.category,
          scopeId: 'Work',
          channel: ReminderChannel.followUp,
          enabled: true,
          leadTime: Duration(hours: 2),
        ),
      );
      resolved = await repository.resolve(
        channel: ReminderChannel.followUp,
        contactId: 'c1',
        category: 'Work',
      );
      expect(resolved.leadTime, const Duration(hours: 2));

      // 3. Contact override
      await repository.savePreference(
        const NotificationPreference(
          scopeType: NotificationScopeType.contact,
          scopeId: 'c1',
          channel: ReminderChannel.followUp,
          enabled: true,
          leadTime: Duration(hours: 3),
        ),
      );
      resolved = await repository.resolve(
        channel: ReminderChannel.followUp,
        contactId: 'c1',
        category: 'Work',
      );
      expect(resolved.leadTime, const Duration(hours: 3));
    });

    test('loadPreferences filtering', () async {
      await repository.savePreference(
        const NotificationPreference(
          scopeType: NotificationScopeType.global,
          scopeId: 'global',
          channel: ReminderChannel.followUp,
          enabled: true,
          leadTime: Duration.zero,
        ),
      );
      await repository.savePreference(
        const NotificationPreference(
          scopeType: NotificationScopeType.contact,
          scopeId: 'c1',
          channel: ReminderChannel.followUp,
          enabled: true,
          leadTime: Duration.zero,
        ),
      );

      final globals = await repository.loadPreferences(
        scopeType: NotificationScopeType.global,
      );
      expect(globals.length, 1);
    });
  });
}
