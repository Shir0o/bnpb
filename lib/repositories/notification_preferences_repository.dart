import '../db/db_helper.dart';
import '../models/notification_preference.dart';

/// Provides accessors and helpers for managing persisted notification
/// preferences.
class NotificationPreferencesRepository {
  NotificationPreferencesRepository({DBHelper? dbHelper})
      : _dbHelper = dbHelper ?? DBHelper();

  final DBHelper _dbHelper;

  /// Ensures a baseline set of global preferences exist for every channel.
  Future<void> ensureDefaults() async {
    for (final channel in ReminderChannel.values) {
      final existing = await _dbHelper.getNotificationPreference(
        scopeType: NotificationScopeType.global,
        scopeId: NotificationPreference.globalScopeId,
        channel: channel,
      );
      if (existing != null) {
        continue;
      }
      await _dbHelper.upsertNotificationPreference(
        NotificationPreference(
          scopeType: NotificationScopeType.global,
          scopeId: NotificationPreference.globalScopeId,
          channel: channel,
          enabled: true,
          leadTime: channel.defaultLeadTime,
        ),
      );
    }
  }

  /// Returns the stored preference for [scopeType]/[scopeId], if available.
  Future<NotificationPreference?> fetchPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) {
    return _dbHelper.getNotificationPreference(
      scopeType: scopeType,
      scopeId: scopeId,
      channel: channel,
    );
  }

  /// Saves (or replaces) a specific preference value.
  Future<NotificationPreference> savePreference(
    NotificationPreference preference,
  ) {
    return _dbHelper.upsertNotificationPreference(preference);
  }

  /// Removes an explicit override for the supplied scope/channel.
  Future<void> deletePreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) {
    return _dbHelper.deleteNotificationPreference(
      scopeType: scopeType,
      scopeId: scopeId,
      channel: channel,
    );
  }

  /// Returns all saved preferences, optionally filtered by [scopeType].
  Future<List<NotificationPreference>> loadPreferences({
    NotificationScopeType? scopeType,
  }) {
    return _dbHelper.getNotificationPreferences(scopeType: scopeType);
  }

  /// Resolves the preference that should apply to a given [contactId].
  ///
  /// The priority order is contact -> category -> global. If no stored
  /// preference exists the defaults defined on [ReminderChannel] are used.
  Future<ResolvedNotificationPreference> resolve({
    required ReminderChannel channel,
    required String contactId,
    String? category,
  }) async {
    final contactPreference = await _dbHelper.getNotificationPreference(
      scopeType: NotificationScopeType.contact,
      scopeId: contactId,
      channel: channel,
    );
    if (contactPreference != null) {
      return ResolvedNotificationPreference(
        enabled: contactPreference.enabled,
        leadTime: contactPreference.leadTime,
      );
    }

    final trimmedCategory = category?.trim();
    if (trimmedCategory != null && trimmedCategory.isNotEmpty) {
      final categoryPreference = await _dbHelper.getNotificationPreference(
        scopeType: NotificationScopeType.category,
        scopeId: trimmedCategory,
        channel: channel,
      );
      if (categoryPreference != null) {
        return ResolvedNotificationPreference(
          enabled: categoryPreference.enabled,
          leadTime: categoryPreference.leadTime,
        );
      }
    }

    final globalPreference = await _dbHelper.getNotificationPreference(
      scopeType: NotificationScopeType.global,
      scopeId: NotificationPreference.globalScopeId,
      channel: channel,
    );
    if (globalPreference != null) {
      return ResolvedNotificationPreference(
        enabled: globalPreference.enabled,
        leadTime: globalPreference.leadTime,
      );
    }

    return ResolvedNotificationPreference(
      enabled: true,
      leadTime: channel.defaultLeadTime,
    );
  }
}
