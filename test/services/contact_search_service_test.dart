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
              occurredAt: DateTime.now(),
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
        ),
      ];
      service.index(contacts);
    });

    test('search finds matches by name', () {
      final results = service.search('Alice');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Alice');
      expect(results.first.score, greaterThan(0));
    });

    test('search finds matches by nickname', () {
      final results = service.search('Ali');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.id, 'c1');
    });

    test('search finds matches by location', () {
      final results = service.search('York');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Bob');
    });

    test('search finds matches in tags', () {
      final results = service.search('friend');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Alice');
    });

    test('search finds matches in interaction summary', () {
      final results = service.search('Starbucks');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Bob');
    });

    test('search finds matches in meeting notes', () {
      final results = service.search('conference');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.firstName, 'Carol');
    });

    test('searchMeetingContexts finds matches', () {
      final results = service.searchMeetingContexts('conference');
      expect(results.isNotEmpty, true);
      expect(results.first.contact.id, 'c3');
      expect(results.first.matchDescription, 'First meeting notes');
    });

    test('empty query returns all contacts with 0 score (normal search)', () {
      final results = service.search('');
      expect(results.length, 3);
      expect(results.first.score, 0);
    });

    test('empty query returns empty list (context search)', () {
      final results = service.searchMeetingContexts('');
      expect(results, isEmpty);
    });
  });
}
