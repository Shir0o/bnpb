import 'package:flutter/foundation.dart';

/// Identifies the notification stream that reminders can be scheduled on.
///
enum ReminderChannel {
  /// Reminders that prompt the user to follow up after an interaction.
  followUp,

  /// Nudges to review or update an outstanding prayer request.
  prayerUpdate,

  /// Significant-date reminders surfaced directly on a contact profile.
  significantDate,

  /// Weekly digest that highlights outstanding prayer requests to revisit.
  weeklyReview,

  /// Monthly digest that surfaces contacts without recent interactions.
  monthlyReview,
}

/// Convenience helpers for [ReminderChannel].
extension ReminderChannelX on ReminderChannel {
  /// Human readable label used throughout the UI.
  String get label {
    switch (this) {
      case ReminderChannel.followUp:
        return 'Follow-up reminders';
      case ReminderChannel.prayerUpdate:
        return 'Prayer updates';
      case ReminderChannel.significantDate:
        return 'Significant dates';
      case ReminderChannel.weeklyReview:
        return 'Weekly review prompts';
      case ReminderChannel.monthlyReview:
        return 'Monthly review prompts';
    }
  }

  /// Default lead time applied when no preference has been saved yet.
  Duration get defaultLeadTime {
    switch (this) {
      case ReminderChannel.followUp:
        return const Duration(hours: 1);
      case ReminderChannel.prayerUpdate:
        return const Duration(days: 1);
      case ReminderChannel.significantDate:
        return const Duration(days: 3);
      case ReminderChannel.weeklyReview:
        return Duration.zero;
      case ReminderChannel.monthlyReview:
        return Duration.zero;
    }
  }

  /// Short description that clarifies how the reminder will be scheduled.
  String get description {
    switch (this) {
      case ReminderChannel.followUp:
        return 'Alerts scheduled before the follow-up time recorded on an interaction.';
      case ReminderChannel.prayerUpdate:
        return 'Reminders triggered after a prayer request has remained pending.';
      case ReminderChannel.significantDate:
        return 'Notifications sent ahead of birthdays, anniversaries, and other cues.';
      case ReminderChannel.weeklyReview:
        return 'Monday summaries linking to pending prayer requests that still need updates.';
      case ReminderChannel.monthlyReview:
        return 'Monthly nudges calling out contacts that have gone quiet.';
    }
  }
}

/// Defines the scope that a notification preference applies to.
enum NotificationScopeType {
  /// Default configuration applied across the entire application.
  global,

  /// Overrides that apply to a specific contact.
  contact,

  /// Overrides driven by interaction or prayer categories.
  category,
}

/// Persistent model describing the notification configuration for a scope
/// and reminder channel.
@immutable
class NotificationPreference {
  /// Constructs a preference definition.
  const NotificationPreference({
    this.id,
    required this.scopeType,
    required this.scopeId,
    required this.channel,
    required this.enabled,
    required this.leadTime,
  });

  /// Database identifier for the row.
  final int? id;

  /// Scope the preference applies to.
  final NotificationScopeType scopeType;

  /// Identifier within the [scopeType].
  final String scopeId;

  /// Reminder channel being configured.
  final ReminderChannel channel;

  /// Whether the reminder should be delivered.
  final bool enabled;

  /// Lead time offset used to adjust the scheduled notification time.
  final Duration leadTime;

  /// Scope identifier for global preferences stored in persistence.
  static const String globalScopeId = 'global';

  /// Creates a copy with selective overrides.
  NotificationPreference copyWith({
    int? id,
    NotificationScopeType? scopeType,
    String? scopeId,
    ReminderChannel? channel,
    bool? enabled,
    Duration? leadTime,
  }) {
    return NotificationPreference(
      id: id ?? this.id,
      scopeType: scopeType ?? this.scopeType,
      scopeId: scopeId ?? this.scopeId,
      channel: channel ?? this.channel,
      enabled: enabled ?? this.enabled,
      leadTime: leadTime ?? this.leadTime,
    );
  }

  /// Serialises the preference into a map for storage.
  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = <String, dynamic>{
      'scopeType': scopeType.name,
      'scopeId': scopeId,
      'channel': channel.name,
      'enabled': enabled ? 1 : 0,
      'leadTimeMinutes': leadTime.inMinutes,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  /// Restores a preference from persistence.
  factory NotificationPreference.fromMap(Map<String, dynamic> map) {
    return NotificationPreference(
      id: map['id'] as int?,
      scopeType: NotificationScopeType.values.firstWhere(
        (value) => value.name == map['scopeType'],
        orElse: () => NotificationScopeType.global,
      ),
      scopeId: map['scopeId'] as String,
      channel: ReminderChannel.values.firstWhere(
        (value) => value.name == map['channel'],
        orElse: () => ReminderChannel.followUp,
      ),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      leadTime: Duration(minutes: map['leadTimeMinutes'] as int? ?? 0),
    );
  }
}

/// Convenience structure produced by resolving preferences through the
/// priority order (contact > category > global).
class ResolvedNotificationPreference {
  /// Creates a resolved configuration.
  const ResolvedNotificationPreference({
    required this.enabled,
    required this.leadTime,
  });

  /// Whether the reminder should be delivered for the evaluated scope.
  final bool enabled;

  /// Lead time to apply before scheduling the notification.
  final Duration leadTime;
}
