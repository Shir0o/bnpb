import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/recurring_log_pattern.dart';
import 'package:bnpb/services/recurring_log_pattern_service.dart';
import 'package:bnpb/services/recurring_log_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const contactId = 'contact-1';
  const key = 'contact-1@@bible reading@@coffee';

  Interaction reading(DateTime date, String notes) {
    return Interaction(
      id: date.day,
      participantIds: const [contactId],
      occurredAt: date,
      summary: 'Bible reading',
      medium: 'Coffee',
      durationMinutes: 45,
      notes: notes,
    );
  }

  List<Contact> contactsWith(List<Interaction> interactions) {
    return [
      Contact(
        id: contactId,
        firstName: 'Timothy',
        lastName: 'Alvarez',
        updatedAt: DateTime(2026, 9, 14),
        interactions: interactions,
      ),
    ];
  }

  RecurringLogPreferences confirmedPreferences({int? spanOverride}) {
    return RecurringLogPreferences({
      key: RecurringLogPreference(
        confirmed: true,
        spanOverride: spanOverride,
      ),
    });
  }

  Contact soloContact(String id, String firstName,
      {List<Interaction>? interactions}) {
    return Contact(
      id: id,
      firstName: firstName,
      lastName: 'Tester',
      updatedAt: DateTime(2026, 9, 14),
      interactions: interactions ?? <Interaction>[],
    );
  }

  Interaction groupReading(DateTime date, List<String> participants) {
    return Interaction(
      participantIds: participants,
      occurredAt: date,
      summary: 'Bible reading',
      medium: 'Coffee',
      durationMinutes: 45,
      notes: 'Psa. 1-2',
    );
  }

  final weekdays = [
    DateTime(2026, 9, 7),
    DateTime(2026, 9, 8),
    DateTime(2026, 9, 9),
    DateTime(2026, 9, 10),
    DateTime(2026, 9, 11),
    DateTime(2026, 9, 12),
  ];

  test('detects a Mon-Sat Bible reading pattern and infers a 2-chapter span',
      () {
    final service = RecurringLogPatternService();
    final interactions = [
      reading(DateTime(2026, 9, 7), 'Psa. 115-116'),
      reading(DateTime(2026, 9, 8), 'Psa. 117-118'),
      reading(DateTime(2026, 9, 9), 'Psa. 119-120'),
      reading(DateTime(2026, 9, 10), 'Psa. 121-122'),
      reading(DateTime(2026, 9, 11), 'Psa. 123-124'),
      reading(DateTime(2026, 9, 12), 'Psa. 125-126'),
    ];

    final patterns = service.detectPatterns(
      contactsWith(interactions),
      now: DateTime(2026, 9, 14, 10),
    );

    expect(patterns, hasLength(1));
    expect(patterns.first.cadence.description, 'Mon-Sat');
    expect(patterns.first.inferredSpan, 2);
    expect(patterns.first.usesScripturePayload, isTrue);
  });

  test(
      'returns a pending confirmation instead of a suggestion before confirmation',
      () {
    final service = RecurringLogPatternService();
    final interactions = [
      reading(DateTime(2026, 9, 7), 'Psa. 115-116'),
      reading(DateTime(2026, 9, 8), 'Psa. 117-118'),
      reading(DateTime(2026, 9, 9), 'Psa. 119-120'),
      reading(DateTime(2026, 9, 10), 'Psa. 121-122'),
      reading(DateTime(2026, 9, 11), 'Psa. 123-124'),
      reading(DateTime(2026, 9, 12), 'Psa. 125-126'),
    ];

    final result = service.buildDueSuggestions(
      contacts: contactsWith(interactions),
      now: DateTime(2026, 9, 14, 10),
      preferences: RecurringLogPreferences(),
    );

    expect(result.suggestions, isEmpty);
    expect(result.pendingConfirmations, hasLength(1));
    expect(result.pendingConfirmations.first.pattern.key, key);
  });

  test('advances by the inferred 2-chapter span for a confirmed routine', () {
    final service = RecurringLogPatternService();
    final interactions = [
      reading(DateTime(2026, 9, 7), 'Psa. 115-116'),
      reading(DateTime(2026, 9, 8), 'Psa. 117-118'),
      reading(DateTime(2026, 9, 9), 'Psa. 119-120'),
      reading(DateTime(2026, 9, 10), 'Psa. 121-122'),
      reading(DateTime(2026, 9, 11), 'Psa. 123-124'),
      reading(DateTime(2026, 9, 12), 'Psa. 125-126'),
    ];

    final result = service.buildDueSuggestions(
      contacts: contactsWith(interactions),
      now: DateTime(2026, 9, 14, 10),
      preferences: confirmedPreferences(),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.first.pill, 'Psa. 127\u2013128');
    expect(result.suggestions.first.isOverdue, isFalse);
  });

  test('crosses into the next book when the span reaches the end of a book',
      () {
    final service = RecurringLogPatternService();
    final interactions = [
      reading(DateTime(2026, 9, 7), 'Psa. 143-144'),
      reading(DateTime(2026, 9, 8), 'Psa. 145-146'),
      reading(DateTime(2026, 9, 9), 'Psa. 147-148'),
      reading(DateTime(2026, 9, 10), 'Psa. 149-150'),
      reading(DateTime(2026, 9, 11), 'Psa. 149-150'),
      reading(DateTime(2026, 9, 12), 'Psa. 149-150'),
    ];

    final result = service.buildDueSuggestions(
      contacts: contactsWith(interactions),
      now: DateTime(2026, 9, 14, 10),
      preferences: confirmedPreferences(),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.first.pill, 'Prov. 1\u20132');
  });

  test('does not invent a reference past the end of Revelation', () {
    final service = RecurringLogPatternService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final interactions = [
      reading(today.subtract(const Duration(days: 21)), 'Rev 22'),
      reading(today.subtract(const Duration(days: 14)), 'Rev 22'),
      reading(today.subtract(const Duration(days: 7)), 'Rev 22'),
    ];

    final result = service.buildDueSuggestions(
      contacts: contactsWith(interactions),
      now: now,
      preferences: confirmedPreferences(),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.first.pill, isNull);
  });

  test('marks a missed cadence day as overdue', () {
    final service = RecurringLogPatternService();
    final interactions = [
      reading(DateTime(2026, 8, 29), 'Psa. 115-116'),
      reading(DateTime(2026, 8, 31), 'Psa. 117-118'),
      reading(DateTime(2026, 9, 1), 'Psa. 119-120'),
      reading(DateTime(2026, 9, 2), 'Psa. 121-122'),
      reading(DateTime(2026, 9, 3), 'Psa. 123-124'),
      reading(DateTime(2026, 9, 4), 'Psa. 125-126'),
      reading(DateTime(2026, 9, 5), 'Psa. 127-128'),
      reading(DateTime(2026, 9, 7), 'Psa. 129-130'),
      reading(DateTime(2026, 9, 8), 'Psa. 131-132'),
      reading(DateTime(2026, 9, 9), 'Psa. 133-134'),
      reading(DateTime(2026, 9, 10), 'Psa. 135-136'),
      reading(DateTime(2026, 9, 11), 'Psa. 137-138'),
    ];

    final result = service.buildDueSuggestions(
      contacts: contactsWith(interactions),
      now: DateTime(2026, 9, 14, 10),
      preferences: confirmedPreferences(),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.first.isOverdue, isTrue);
    expect(result.suggestions.first.overdueDays, 2);
  });

  test('groups a shared engagement across contacts into one pattern', () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    final bob = soloContact('bob', 'Bob');
    final carol = soloContact('carol', 'Carol');
    for (final date in weekdays) {
      for (final contact in [alice, bob, carol]) {
        contact.interactions
            .add(groupReading(date, const ['alice', 'bob', 'carol']));
      }
    }

    final patterns = service.detectPatterns(
      [alice, bob, carol],
      now: DateTime(2026, 9, 14),
    );

    expect(patterns, hasLength(1));
    expect(patterns.first.identity.participantIds, ['alice', 'bob', 'carol']);
    expect(patterns.first.occurrenceCount, 6);
  });

  test('a subset attending one week still belongs to the shared pattern', () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    final bob = soloContact('bob', 'Bob');
    final carol = soloContact('carol', 'Carol');
    for (final date in weekdays.take(4)) {
      for (final contact in [alice, bob, carol]) {
        contact.interactions
            .add(groupReading(date, const ['alice', 'bob', 'carol']));
      }
    }
    for (final date in weekdays.skip(4)) {
      alice.interactions.add(groupReading(date, const ['alice', 'bob']));
      bob.interactions.add(groupReading(date, const ['alice', 'bob']));
    }

    final patterns = service.detectPatterns(
      [alice, bob, carol],
      now: DateTime(2026, 9, 14),
    );

    expect(patterns, hasLength(1));
    expect(
      patterns.first.identity.participantIds,
      containsAll(['alice', 'bob', 'carol']),
    );
    expect(patterns.first.occurrenceCount, 6);
  });

  test('recording a partial-attendance occurrence satisfies the cadence day',
      () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    final bob = soloContact('bob', 'Bob');
    final carol = soloContact('carol', 'Carol');
    for (final date in weekdays) {
      for (final contact in [alice, bob, carol]) {
        contact.interactions
            .add(groupReading(date, const ['alice', 'bob', 'carol']));
      }
    }
    final contacts = [alice, bob, carol];
    final now = DateTime(2026, 9, 14, 10);

    final detected = service.detectPatterns(contacts, now: now);
    final key = detected.first.key;
    final preferences = RecurringLogPreferences(
        {key: const RecurringLogPreference(confirmed: true)});

    var result = service.buildDueSuggestions(
      contacts: contacts,
      now: now,
      preferences: preferences,
    );
    expect(result.suggestions, hasLength(1));

    alice.interactions.add(
      groupReading(DateTime(2026, 9, 14, 9), const ['alice', 'bob']),
    );

    result = service.buildDueSuggestions(
      contacts: contacts,
      now: now,
      preferences: preferences,
    );
    expect(result.suggestions, isEmpty);
  });

  test('a single-participant pattern resolves the legacy preference key', () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    for (final date in weekdays) {
      alice.interactions.add(groupReading(date, const ['alice']));
    }

    final preferences = RecurringLogPreferences({
      'alice@@bible reading@@coffee':
          const RecurringLogPreference(confirmed: true),
    });

    final result = service.buildDueSuggestions(
      contacts: [alice],
      now: DateTime(2026, 9, 14, 10),
      preferences: preferences,
    );

    expect(result.suggestions, hasLength(1));
  });

  test('combining patterns folds them into one confirmed pattern', () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    final bob = soloContact('bob', 'Bob');
    for (final date in weekdays) {
      alice.interactions.add(groupReading(date, const ['alice']));
      bob.interactions.add(groupReading(date, const ['bob']));
    }
    final contacts = [alice, bob];
    final now = DateTime(2026, 9, 14, 10);

    final detected = service.detectPatterns(contacts, now: now);
    expect(detected, hasLength(2));

    final initialPreferences = RecurringLogPreferences({
      detected.first.key: const RecurringLogPreference(confirmed: true),
    });
    final preferences = service.combinePatterns(
      initialPreferences,
      detected.first,
      [detected.last],
    );

    final resolved = service.resolvePatterns(detected, preferences);
    expect(resolved, hasLength(1));
    expect(resolved.first.identity.participantIds, ['alice', 'bob']);
    expect(resolved.first.occurrenceCount, 6);

    final result = service.buildDueSuggestions(
      contacts: contacts,
      now: now,
      preferences: preferences,
    );
    expect(result.suggestions, hasLength(1));
    expect(
      result.suggestions.first.pattern.key,
      'bible reading@@coffee@@alice,bob',
    );
  });

  test('combining unconfirmed patterns yields a pending confirmation', () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    final bob = soloContact('bob', 'Bob');
    for (final date in weekdays) {
      alice.interactions.add(groupReading(date, const ['alice']));
      bob.interactions.add(groupReading(date, const ['bob']));
    }
    final contacts = [alice, bob];
    final now = DateTime(2026, 9, 14, 10);

    final detected = service.detectPatterns(contacts, now: now);
    final preferences = service.combinePatterns(
      RecurringLogPreferences(),
      detected.first,
      [detected.last],
    );

    final result = service.buildDueSuggestions(
      contacts: contacts,
      now: now,
      preferences: preferences,
    );
    expect(result.suggestions, isEmpty);
    expect(result.pendingConfirmations, hasLength(1));
    expect(
      result.pendingConfirmations.first.pattern.key,
      'bible reading@@coffee@@alice,bob',
    );
  });

  test('rekeying a pattern keeps preferences under the new identity', () {
    final service = RecurringLogPatternService();
    final alice = soloContact('alice', 'Alice');
    for (final date in weekdays) {
      alice.interactions.add(groupReading(date, const ['alice']));
    }
    final contacts = [alice];
    final now = DateTime(2026, 9, 14, 10);

    final detected = service.detectPatterns(contacts, now: now);
    expect(detected.first.key, 'alice@@bible reading@@coffee');

    final newIdentity = const PatternIdentity(
      activity: 'bible reading',
      medium: 'coffee',
      participantIds: ['alice', 'bob'],
    );
    final preferences = service.rekeyPattern(
      RecurringLogPreferences(),
      detected.first.key,
      newIdentity,
      RecurringLogPreference(
        confirmed: true,
        canonicalIdentity: newIdentity,
      ),
    );

    final resolved = service.resolvePatterns(detected, preferences);
    expect(resolved, hasLength(1));
    expect(resolved.first.key, 'bible reading@@coffee@@alice,bob');
    expect(resolved.first.identity.participantIds, ['alice', 'bob']);

    final result = service.buildDueSuggestions(
      contacts: contacts,
      now: now,
      preferences: preferences,
    );
    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.first.contact.id, 'alice');
  });
}
