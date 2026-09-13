import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
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
}
