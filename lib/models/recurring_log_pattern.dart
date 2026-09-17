import 'interaction.dart';
import 'contact.dart';

/// Stable identity for a recurring log pattern.
///
/// Identity is engagement-scoped: it is the normalized activity and medium
/// together with the regular participant Contact ids, independent of who
/// attends any individual occurrence.
class PatternIdentity {
  const PatternIdentity({
    required this.activity,
    required this.medium,
    required this.participantIds,
  });

  final String activity;
  final String medium;

  /// Regular participant Contact ids, sorted and unique.
  final List<String> participantIds;

  /// The key under which pattern preferences are persisted. Single-participant
  /// patterns keep the legacy `contact@@activity@@medium` shape so existing
  /// saved preferences still resolve.
  String get key {
    if (participantIds.length == 1) {
      return '${participantIds.first}@@$activity@@$medium';
    }
    return '$activity@@$medium@@${participantIds.join(',')}';
  }

  /// Builds an identity from the raw activity, medium, and regular
  /// participant Contact ids, normalizing activity/medium and sorting ids.
  static PatternIdentity fromOccurrence({
    required String activity,
    required String medium,
    required Set<String> participantIds,
  }) {
    final sorted = participantIds.toList()..sort();
    return PatternIdentity(
      activity: normalize(activity),
      medium: normalize(medium),
      participantIds: sorted,
    );
  }

  static String normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Map<String, dynamic> toJson() {
    return {
      'activity': activity,
      'medium': medium,
      'participantIds': participantIds,
    };
  }

  /// Restores an identity from [PatternIdentity.toJson] output, or null when
  /// the payload is malformed.
  static PatternIdentity? fromJson(Map<String, dynamic> json) {
    final activity = json['activity'];
    final medium = json['medium'];
    final raw = json['participantIds'];
    if (activity is! String || medium is! String) return null;
    if (raw is! List) return null;
    final ids = raw
        .map((entry) => entry.toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (ids.isEmpty) return null;
    return PatternIdentity(
      activity: activity,
      medium: medium,
      participantIds: ids,
    );
  }
}

/// Timing rule for a recurring log pattern.
class PatternCadence {
  const PatternCadence.weekdays(Set<int> this.weekdays)
      : intervalDays = null,
        anchorDate = null;

  const PatternCadence.interval(int this.intervalDays, DateTime this.anchorDate)
      : weekdays = null;

  final Set<int>? weekdays;
  final int? intervalDays;
  final DateTime? anchorDate;

  bool get isWeekdays => weekdays != null;

  bool expects(DateTime date) {
    final days = weekdays;
    if (days != null) {
      return days.contains(date.weekday);
    }
    final interval = intervalDays;
    final anchor = anchorDate;
    if (interval == null || anchor == null) return false;
    final diff = dateOnly(date).difference(dateOnly(anchor)).inDays;
    return diff >= interval;
  }

  /// Most recent expected day strictly before [date].
  DateTime? previousExpectedDate(DateTime date) {
    final today = dateOnly(date);
    final days = weekdays;
    if (days != null) {
      for (var offset = 1; offset <= 7; offset++) {
        final candidate = today.subtract(Duration(days: offset));
        if (days.contains(candidate.weekday)) return candidate;
      }
      return null;
    }
    final interval = intervalDays;
    final anchor = anchorDate;
    if (interval == null || anchor == null) return null;
    final expected = dateOnly(anchor).add(Duration(days: interval));
    return expected.isBefore(today) ? expected : null;
  }

  String get description {
    final days = weekdays;
    if (days != null) {
      if (days.length == 7) return 'Every day';
      if (days.length == 6 &&
          days.contains(DateTime.monday) &&
          days.contains(DateTime.tuesday) &&
          days.contains(DateTime.wednesday) &&
          days.contains(DateTime.thursday) &&
          days.contains(DateTime.friday) &&
          days.contains(DateTime.saturday)) {
        return 'Mon-Sat';
      }
      final sorted = days.toList()..sort();
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return sorted.map((day) => names[day - 1]).join(', ');
    }
    return 'Every $intervalDays days';
  }

  Map<String, dynamic> toJson() {
    final days = weekdays;
    if (days != null) {
      return {'type': 'weekdays', 'days': (days.toList()..sort())};
    }
    return {
      'type': 'interval',
      'intervalDays': intervalDays,
      'anchorDate': anchorDate?.toIso8601String(),
    };
  }

  static PatternCadence? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type == 'weekdays') {
      final rawDays = json['days'];
      if (rawDays is List) {
        final days = rawDays.whereType<num>().map((day) => day.toInt()).toSet();
        if (days.isNotEmpty) return PatternCadence.weekdays(days);
      }
      return null;
    }
    if (type == 'interval') {
      final interval = json['intervalDays'];
      final anchorRaw = json['anchorDate'];
      if (interval is num && anchorRaw is String) {
        final anchor = DateTime.tryParse(anchorRaw);
        if (anchor != null) {
          return PatternCadence.interval(interval.toInt(), anchor);
        }
      }
    }
    return null;
  }
}

class RecurringLogPattern {
  const RecurringLogPattern({
    required this.identity,
    required this.displayActivity,
    required this.cadence,
    required this.occurrenceCount,
    required this.lastOccurredAt,
    required this.inferredSpan,
    required this.usesScripturePayload,
    required this.matchingInteractions,
  });

  final PatternIdentity identity;
  final String displayActivity;
  final PatternCadence cadence;
  final int occurrenceCount;
  final DateTime lastOccurredAt;
  final int inferredSpan;
  final bool usesScripturePayload;
  final List<Interaction> matchingInteractions;

  String get key => identity.key;
}

class PendingRoutine {
  const PendingRoutine({
    required this.pattern,
    required this.contact,
    required this.latestInteraction,
    required this.isOverdue,
    required this.overdueDays,
  });

  final RecurringLogPattern pattern;
  final Contact contact;
  final Interaction latestInteraction;
  final bool isOverdue;
  final int overdueDays;
}

class ReadyToLogSuggestion {
  const ReadyToLogSuggestion({
    required this.pattern,
    required this.contact,
    required this.latestInteraction,
    required this.pill,
    required this.prefillNotes,
    required this.isOverdue,
    required this.overdueDays,
  });

  final RecurringLogPattern pattern;
  final Contact contact;
  final Interaction latestInteraction;
  final String? pill;
  final String? prefillNotes;
  final bool isOverdue;
  final int overdueDays;

  ReadyToLogSuggestion copyWith({
    String? pill,
    String? prefillNotes,
  }) {
    return ReadyToLogSuggestion(
      pattern: pattern,
      contact: contact,
      latestInteraction: latestInteraction,
      pill: pill ?? this.pill,
      prefillNotes: prefillNotes ?? this.prefillNotes,
      isOverdue: isOverdue,
      overdueDays: overdueDays,
    );
  }
}

class RecurringLogResult {
  const RecurringLogResult({
    this.suggestions = const [],
    this.pendingConfirmations = const [],
  });

  final List<ReadyToLogSuggestion> suggestions;
  final List<PendingRoutine> pendingConfirmations;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
