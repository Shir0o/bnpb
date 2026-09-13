import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/recurring_log_pattern.dart';
import 'ai/scripture_ref.dart';
import 'recurring_log_preferences.dart';

class RecurringLogPatternService {
  const RecurringLogPatternService({
    this.lookbackDays = 90,
    this.retireAfterDays = 45,
    this.minOccurrences = 3,
  });

  final int lookbackDays;
  final int retireAfterDays;
  final int minOccurrences;

  List<RecurringLogPattern> detectPatterns(
    List<Contact> contacts, {
    required DateTime now,
  }) {
    final cutoff = dateOnly(now).subtract(Duration(days: lookbackDays));
    final patterns = <RecurringLogPattern>[];

    for (final contact in contacts) {
      final groups = <String, List<Interaction>>{};
      for (final interaction in contact.interactions) {
        if (interaction.summary.trim().isEmpty) continue;
        final occurred = dateOnly(interaction.occurredAt);
        if (occurred.isBefore(cutoff)) continue;
        final identity =
            PatternIdentity.fromInteraction(contact.id, interaction);
        groups.putIfAbsent(identity.key, () => []).add(interaction);
      }

      for (final group in groups.values) {
        group.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        if (group.length < minOccurrences) continue;
        final latest = group.first;
        if (dateOnly(now).difference(dateOnly(latest.occurredAt)).inDays >
            retireAfterDays) {
          continue;
        }
        final cadence = _inferCadence(group);
        if (cadence == null) continue;
        final latestNotes = latest.notes;
        final usesScripture = group.any(_hasScripturePayload) ||
            _looksLikeScripture(latest.summary) ||
            (latestNotes != null && _looksLikeScripture(latestNotes));
        patterns.add(
          RecurringLogPattern(
            identity: PatternIdentity.fromInteraction(contact.id, latest),
            displayActivity: latest.summary.trim(),
            cadence: cadence,
            occurrenceCount: group.length,
            lastOccurredAt: latest.occurredAt,
            inferredSpan: _inferSpan(group),
            usesScripturePayload: usesScripture,
            matchingInteractions: List<Interaction>.from(group),
          ),
        );
      }
    }

    return patterns;
  }

  RecurringLogResult buildDueSuggestions({
    required List<Contact> contacts,
    required DateTime now,
    required RecurringLogPreferences preferences,
    int maxSuggestions = 3,
  }) {
    final patterns = detectPatterns(contacts, now: now);
    final contactById = {for (final contact in contacts) contact.id: contact};
    final suggestions = <ReadyToLogSuggestion>[];
    final pending = <PendingRoutine>[];

    for (final pattern in patterns) {
      final preference = preferences.preferenceFor(pattern.key);
      if (preference.suppressed) continue;
      if (_isSnoozed(preference, now)) continue;

      final due = _dueStatus(pattern, now);
      if (due == null) continue;
      final contact = contactById[pattern.identity.contactId];
      if (contact == null) continue;
      final latest = pattern.matchingInteractions.first;

      if (preference.confirmed) {
        final payload = _buildPayload(pattern, preference);
        suggestions.add(
          ReadyToLogSuggestion(
            pattern: pattern,
            contact: contact,
            latestInteraction: latest,
            pill: payload.pill,
            prefillNotes: payload.prefillNotes,
            isOverdue: due.isOverdue,
            overdueDays: due.overdueDays,
          ),
        );
      } else {
        pending.add(
          PendingRoutine(
            pattern: pattern,
            contact: contact,
            latestInteraction: latest,
            isOverdue: due.isOverdue,
            overdueDays: due.overdueDays,
          ),
        );
      }
    }

    suggestions.sort((a, b) {
      final overdue = b.overdueDays.compareTo(a.overdueDays);
      if (overdue != 0) return overdue;
      final confidence =
          b.pattern.occurrenceCount.compareTo(a.pattern.occurrenceCount);
      if (confidence != 0) return confidence;
      return _payloadRank(b).compareTo(_payloadRank(a));
    });
    pending.sort((a, b) => b.overdueDays.compareTo(a.overdueDays));

    return RecurringLogResult(
      suggestions: suggestions.take(maxSuggestions).toList(),
      pendingConfirmations: pending.take(1).toList(),
    );
  }

  PatternCadence? _inferCadence(List<Interaction> interactions) {
    final dates = interactions
        .map((interaction) => dateOnly(interaction.occurredAt))
        .toSet()
        .toList()
      ..sort();
    if (dates.length < 3) return null;

    final intervals = <int>[];
    for (var i = 1; i < dates.length; i++) {
      intervals.add(dates[i].difference(dates[i - 1]).inDays);
    }
    final medianInterval = _median(intervals);
    final weekdayCounts = <int, int>{};
    for (final date in dates) {
      weekdayCounts.update(date.weekday, (count) => count + 1,
          ifAbsent: () => 1);
    }

    PatternCadence? cadence;
    if (medianInterval <= 2 && weekdayCounts.length >= 4) {
      final weekdays = _dominantWeekdays(weekdayCounts);
      if (weekdays.length >= 4) {
        cadence = PatternCadence.weekdays(weekdays);
      }
    }

    if (cadence == null && weekdayCounts.length <= 4) {
      final weekdays = _dominantWeekdays(weekdayCounts);
      if (weekdays.length == weekdayCounts.length && weekdays.isNotEmpty) {
        cadence = PatternCadence.weekdays(weekdays);
      }
    }

    if (cadence == null) {
      final rounded = medianInterval.round();
      final regular =
          intervals.every((interval) => (interval - rounded).abs() <= 1);
      if (rounded >= 2 && regular) {
        cadence = PatternCadence.interval(rounded, dates.last);
      }
    }

    if (cadence == null) return null;
    if (_hasRepeatedInterval(intervals) == false) return null;
    return cadence;
  }

  bool _hasRepeatedInterval(List<int> intervals) {
    return intervals.toSet().length < intervals.length;
  }

  Set<int> _dominantWeekdays(Map<int, int> counts) {
    final maxCount = counts.values.reduce((a, b) => a > b ? a : b);
    final threshold = maxCount >= 2 ? 2 : 1;
    final weekdays = <int>{
      for (final entry in counts.entries)
        if (entry.value >= threshold) entry.key,
    };
    return weekdays.isEmpty ? counts.keys.toSet() : weekdays;
  }

  int _inferSpan(List<Interaction> interactions) {
    final spans = <int>[];
    for (final interaction in interactions.take(5)) {
      final notes = interaction.notes;
      final summary = interaction.summary;
      final fromNotes = notes == null ? 0 : _scriptureSpan(notes);
      final fromSummary = _scriptureSpan(summary);
      final span = fromNotes > 0 ? fromNotes : fromSummary;
      if (span > 0) spans.add(span);
    }
    if (spans.isEmpty) return 1;
    return _median(spans);
  }

  int _scriptureSpan(String text) {
    final refs = ScriptureRef.tryParseAll(text);
    if (refs.isEmpty) return 0;
    var total = 0;
    for (final ref in refs) {
      total += ref.chaptersRead;
    }
    return total;
  }

  bool _hasScripturePayload(Interaction interaction) {
    final notes = interaction.notes;
    if (notes != null && _scriptureSpan(notes) > 0) return true;
    return _scriptureSpan(interaction.summary) > 0;
  }

  bool _looksLikeScripture(String text) {
    final lower = text.toLowerCase();
    return lower.contains('bible') ||
        lower.contains('scripture') ||
        lower.contains('psalm') ||
        lower.contains('proverb') ||
        lower.contains('verse') ||
        lower.contains('chapter');
  }

  _DueStatus? _dueStatus(RecurringLogPattern pattern, DateTime now) {
    final today = dateOnly(now);
    final lastDate = dateOnly(pattern.lastOccurredAt);
    if (lastDate == today) return null;

    final cadence = pattern.cadence;
    if (cadence.isWeekdays) {
      if (cadence.expects(now) == false) return null;
      final previous = cadence.previousExpectedDate(now);
      if (previous == null) return null;
      final missed = lastDate.isBefore(previous);
      final overdueDays = missed ? today.difference(previous).inDays : 0;
      return _DueStatus(isOverdue: missed, overdueDays: overdueDays);
    }

    final interval = cadence.intervalDays;
    final anchor = cadence.anchorDate;
    if (interval == null || anchor == null) return null;
    final daysSince = today.difference(dateOnly(anchor)).inDays;
    if (daysSince < interval) return null;
    return _DueStatus(
      isOverdue: daysSince > interval,
      overdueDays: daysSince - interval,
    );
  }

  _Payload _buildPayload(
    RecurringLogPattern pattern,
    RecurringLogPreference preference,
  ) {
    final latest = pattern.matchingInteractions.first;
    if (pattern.usesScripturePayload == false) {
      return _Payload(pill: null, prefillNotes: latest.notes);
    }

    final current = ScriptureRef.tryParseLast(latest.notes) ??
        ScriptureRef.tryParseLast(latest.summary);
    if (current == null) {
      return _Payload(pill: null, prefillNotes: latest.notes);
    }

    final span = preference.spanOverride ?? pattern.inferredSpan;
    final passage = current.nextPassage(chapters: span);
    if (passage != null) {
      return _Payload(pill: passage.display, prefillNotes: passage.display);
    }
    if (current.hasKnownBook) {
      return _Payload(pill: null, prefillNotes: latest.notes);
    }

    final fallback = current.advance().display;
    return _Payload(pill: fallback, prefillNotes: fallback);
  }

  bool _isSnoozed(RecurringLogPreference preference, DateTime now) {
    final snoozedUntil = preference.snoozedUntil;
    if (snoozedUntil == null) return false;
    return dateOnly(now).isBefore(dateOnly(snoozedUntil));
  }

  int _payloadRank(ReadyToLogSuggestion suggestion) =>
      suggestion.pill == null ? 0 : 1;

  int _median(List<int> values) {
    final sorted = List<int>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }
}

class _DueStatus {
  const _DueStatus({required this.isOverdue, required this.overdueDays});

  final bool isOverdue;
  final int overdueDays;
}

class _Payload {
  const _Payload({required this.pill, required this.prefillNotes});

  final String? pill;
  final String? prefillNotes;
}
