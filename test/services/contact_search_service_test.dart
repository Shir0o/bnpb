import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/contact_search_service.dart';

void main() {
  group('ContactSearchService', () {
    late ContactSearchService service;
    late List<Contact> contacts;

    setUp(() {
      service = ContactSearchService();
      contacts = [
        Contact(
          id: 'c1',
          firstName: 'Alice',
          lastName: 'Smith',
          nickname: 'Ali',
          interactions: [],
          tags: ['Friend', 'Work'],
        ),
        Contact(
          id: 'c2',
          firstName: 'Bob',
          lastName: 'Jones',
          location: 'New York',
          interactions: [
            Interaction(
              occurredAt: DateTime.now().subtract(const Duration(days: 5)),
              summary: 'Coffee at Starbucks',
              medium: 'in_person',
            ),
          ],
        ),
        Contact(
          id: 'c3',
          firstName: 'Carol',
          interactions: [],
          firstMeetingNotes: 'Met at conference',
          recognitionKeywords: ['red scarf'],
          recognitionReminders: ['ask about marathon'],
        ),
      ];
      service.index(contacts);
    });

    test('search finds matches by name', () async {
      final results = await service.search('Alice');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Alice');
      expect(results.first.score, greaterThan(0));
    });

    test('search finds matches by nickname', () async {
      final results = await service.search('Ali');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.id, 'c1');
    });

    test('search finds matches by location', () async {
      final results = await service.search('York');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Bob');
    });

    test('search finds matches in tags', () async {
      final results = await service.search('friend');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Alice');
    });

    test('search finds matches in interaction summary', () async {
      final results = await service.search('Starbucks');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Bob');
    });

    test('search finds matches in meeting notes', () async {
      final results = await service.search('conference');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Carol');
    });

    test('search finds matches in recognition cues', () async {
      final keywordResults = await service.search('scarf');
      final reminderResults = await service.search('marathon');

      expect(keywordResults.isNotEmpty, true);
      expect(keywordResults.first.contact.firstName, 'Carol');
      expect(keywordResults.first.matchDescription, 'Recognition keywords');
      expect(reminderResults.isNotEmpty, true);
      expect(reminderResults.first.contact.firstName, 'Carol');
      expect(reminderResults.first.matchDescription, 'Recognition reminders');
    });

    test(
      'empty query returns all contacts with 0 score (normal search)',
      () async {
        final results = await service.search('');
        expect(results.length, 3);
        expect(results.first.score, 0);
      },
    );

    test('getSuggestions returns contacts ranked by recency', () {
      final now = DateTime.now();
      final cRecency = [
        Contact(
          id: 'old',
          firstName: 'Old',
          interactions: [
            Interaction(
              occurredAt: now.subtract(const Duration(days: 10)),
              summary: 'old',
              medium: 'call',
            ),
          ],
        ),
        Contact(
          id: 'new',
          firstName: 'New',
          interactions: [
            Interaction(
              occurredAt: now.subtract(const Duration(days: 1)),
              summary: 'new',
              medium: 'call',
            ),
          ],
        ),
        Contact(id: 'none', firstName: 'None', interactions: []),
      ];
      service.index(cRecency);
      final suggestions = service.getSuggestions();
      expect(suggestions.length, 3);
      expect(suggestions[0].contact.firstName, 'New');
      expect(suggestions[1].contact.firstName, 'Old');
      expect(suggestions[2].contact.firstName, 'None');
      expect(suggestions[0].matchDescription, contains('Last met'));
    });

    test('getSuggestions breaks ties with frequency', () {
      final now = DateTime.now();
      // Both interacting "today", but one has more interactions
      final cFrequency = [
        Contact(
          id: 'frequent',
          firstName: 'Frequent',
          interactions: [
            Interaction(occurredAt: now, summary: '1', medium: 'call'),
            Interaction(occurredAt: now, summary: '2', medium: 'call'),
          ],
        ),
        Contact(
          id: 'once',
          firstName: 'Once',
          interactions: [
            Interaction(occurredAt: now, summary: '1', medium: 'call'),
          ],
        ),
      ];
      service.index(cFrequency);
      final suggestions = service.getSuggestions();
      expect(suggestions.length, 2);
      expect(suggestions[0].contact.firstName, 'Frequent');
      expect(suggestions[1].contact.firstName, 'Once');
    });
  });
}
