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

  /// Detects recurring log patterns across all Contacts.
  ///
  /// Interactions sharing the same normalized activity and medium are grouped,
  /// then clustered into connected components where two interactions belong to
  /// the same recurring engagement when their participant sets overlap (a
  /// subset attending one week still connects to the wider group). A component
  /// becomes one pattern whose regular participants are the union of the
  /// participants across its occurrences.
  List<RecurringLogPattern> detectPatterns(
    List<Contact> contacts, {
    required DateTime now,
  }) {
    final cutoff = dateOnly(now).subtract(Duration(days: lookbackDays));
    final items = <_GroupItem>[];
    for (final contact in contacts) {
      for (final interaction in contact.interactions) {
        if (interaction.summary.trim().isEmpty) continue;
        final occurred = dateOnly(interaction.occurredAt);
        if (occurred.isBefore(cutoff)) continue;
        items.add(_GroupItem(contact.id, interaction));
      }
    }

    final byActivity = <String, List<_GroupItem>>{};
    for (final item in items) {
      final activity = PatternIdentity.normalize(item.interaction.summary);
      final medium = PatternIdentity.normalize(item.interaction.medium);
      byActivity.putIfAbsent('$activity@@$medium', () => []).add(item);
    }

    final patterns = <RecurringLogPattern>[];
    for (final group in byActivity.values) {
      for (final component in _connectedComponents(group)) {
        final interactions = component.map((item) => item.interaction).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        final distinctDates =
            interactions.map((i) => dateOnly(i.occurredAt)).toSet();
        if (distinctDates.length < minOccurrences) continue;

        final latest = interactions.first;
        if (dateOnly(now).difference(dateOnly(latest.occurredAt)).inDays >
            retireAfterDays) {
          continue;
        }

        final cadence = _inferCadence(interactions);
        if (cadence == null) continue;

        final participantIds = <String>{
          for (final item in component) item.contactId,
          for (final item in component) ...item.interaction.participantIds,
        };

        final latestNotes = latest.notes;
        final usesScripture = interactions.any(_hasScripturePayload) ||
            _looksLikeScripture(latest.summary) ||
            (latestNotes != null && _looksLikeScripture(latestNotes));

        patterns.add(
          RecurringLogPattern(
            identity: PatternIdentity.fromOccurrence(
              activity: latest.summary,
              medium: latest.medium,
              participantIds: participantIds,
            ),
            displayActivity: latest.summary.trim(),
            cadence: cadence,
            occurrenceCount: distinctDates.length,
            lastOccurredAt: latest.occurredAt,
            inferredSpan: _inferSpan(interactions),
            usesScripturePayload: usesScripture,
            matchingInteractions: interactions,
          ),
        );
      }
    }

    return patterns;
  }

  /// Folds patterns whose preferences redirect into another pattern (via
  /// [RecurringLogPreference.mergedIntoKey]) into a single combined pattern.
  List<RecurringLogPattern> resolvePatterns(
    List<RecurringLogPattern> detected,
    RecurringLogPreferences preferences,
  ) {
    if (detected.isEmpty) return detected;

    String canonicalKey(String key) {
      final seen = <String>{};
      var current = key;
      while (true) {
        final mergedInto = preferences.get(current)?.mergedIntoKey;
        if (mergedInto == null ||
            mergedInto == current ||
            seen.contains(mergedInto)) {
          return current;
        }
        seen.add(current);
        current = mergedInto;
      }
    }

    final byCanonical = <String, List<RecurringLogPattern>>{};
    for (final pattern in detected) {
      byCanonical.putIfAbsent(canonicalKey(pattern.key), () => []).add(pattern);
    }

    final resolved = <RecurringLogPattern>[];
    for (final entry in byCanonical.entries) {
      final canonical = entry.key;
      final members = entry.value;
      final canonicalPreference = preferences.preferenceFor(canonical);

      final interactions = <Interaction>[
        for (final member in members) ...member.matchingInteractions,
      ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      final primary = members.firstWhere(
        (member) => member.key == canonical,
        orElse: () => members.first,
      );

      final identity = canonicalPreference.canonicalIdentity ??
          PatternIdentity.fromOccurrence(
            activity: primary.identity.activity,
            medium: primary.identity.medium,
            participantIds: {
              for (final member in members) ...member.identity.participantIds,
            },
          );

      final distinctDates =
          interactions.map((i) => dateOnly(i.occurredAt)).toSet();

      resolved.add(
        RecurringLogPattern(
          identity: identity,
          displayActivity: canonicalPreference.displayNameOverride ??
              primary.displayActivity,
          cadence: canonicalPreference.cadenceOverride ?? primary.cadence,
          occurrenceCount: distinctDates.length,
          lastOccurredAt: interactions.first.occurredAt,
          inferredSpan:
              canonicalPreference.spanOverride ?? primary.inferredSpan,
          usesScripturePayload: primary.usesScripturePayload,
          matchingInteractions: interactions,
        ),
      );
    }
    return resolved;
  }

  /// Combines [target] with [sources] into a single pattern, persisting the
  /// combined identity and redirecting the folded patterns' preference keys.
  RecurringLogPreferences combinePatterns(
    RecurringLogPreferences preferences,
    RecurringLogPattern target,
    List<RecurringLogPattern> sources,
  ) {
    final participants = <String>{
      ...target.identity.participantIds,
      for (final source in sources) ...source.identity.participantIds,
    };
    final identity = PatternIdentity.fromOccurrence(
      activity: target.identity.activity,
      medium: target.identity.medium,
      participantIds: participants,
    );
    final targetKey = identity.key;

    final anyConfirmed = preferences.preferenceFor(target.key).confirmed ||
        sources
            .any((source) => preferences.preferenceFor(source.key).confirmed);

    var updated = preferences.withPreference(
      targetKey,
      preferences.preferenceFor(targetKey).copyWith(
            confirmed: anyConfirmed,
            displayNameOverride: target.displayActivity,
            canonicalIdentity: identity,
          ),
    );

    final keysToRedirect = <String>{
      target.key,
      for (final source in sources) source.key,
    }..remove(targetKey);

    for (final key in keysToRedirect) {
      updated = updated.withPreference(
        key,
        preferences.preferenceFor(key).copyWith(mergedIntoKey: targetKey),
      );
    }
    return updated;
  }

  /// Rewrites a pattern's preference to a new identity, redirecting the old
  /// key so previously saved choices survive the change.
  RecurringLogPreferences rekeyPattern(
    RecurringLogPreferences preferences,
    String oldKey,
    PatternIdentity newIdentity,
    RecurringLogPreference preference,
  ) {
    final newKey = newIdentity.key;
    var updated = preferences.withPreference(newKey, preference);
    if (newKey != oldKey) {
      updated = updated.withPreference(
        oldKey,
        preferences.preferenceFor(oldKey).copyWith(mergedIntoKey: newKey),
      );
    }
    return updated;
  }

  RecurringLogResult buildDueSuggestions({
    required List<Contact> contacts,
    required DateTime now,
    required RecurringLogPreferences preferences,
    int maxSuggestions = 3,
  }) {
    final patterns = resolvePatterns(
      detectPatterns(contacts, now: now),
      preferences,
    );
    final contactById = {for (final contact in contacts) contact.id: contact};
    final suggestions = <ReadyToLogSuggestion>[];
    final pending = <PendingRoutine>[];

    for (final pattern in patterns) {
      final preference = preferences.preferenceFor(pattern.key);
      if (preference.suppressed) continue;
      if (_isSnoozed(preference, now)) continue;

      final due = _dueStatus(pattern, now);
      if (due == null) continue;
      final contact = _primaryContact(pattern, contactById);
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

  Contact? _primaryContact(
    RecurringLogPattern pattern,
    Map<String, Contact> contactById,
  ) {
    for (final participantId in pattern.identity.participantIds) {
      final contact = contactById[participantId];
      if (contact != null) return contact;
    }
    return null;
  }

  List<List<_GroupItem>> _connectedComponents(List<_GroupItem> group) {
    final n = group.length;
    if (n <= 1) return [group];

    final parent = List<int>.generate(n, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) parent[rootA] = rootB;
    }

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final a = group[i];
        final b = group[j];
        if (a.participantIds.intersection(b.participantIds).isNotEmpty) {
          union(i, j);
        }
      }
    }

    final buckets = <int, List<_GroupItem>>{};
    for (var i = 0; i < n; i++) {
      buckets.putIfAbsent(find(i), () => []).add(group[i]);
    }
    return buckets.values.toList();
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

class _GroupItem {
  _GroupItem(this.contactId, this.interaction);

  final String contactId;
  final Interaction interaction;

  /// The actual attendees of this interaction. Logged interactions always
  /// include the owning contact in [Interaction.participantIds]; legacy data
  /// with an empty list falls back to the owning contact.
  Set<String> get participantIds {
    final participants = interaction.participantIds;
    return participants.isEmpty ? {contactId} : participants.toSet();
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
