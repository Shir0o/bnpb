import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';

void main() {
  group('Contact', () {
    const contactId = 'contact-123';

    test('props are correctly assigned via constructor', () {
      final contact = Contact(
        id: contactId,
        firstName: 'John',
        lastName: 'Doe',
        tags: ['Friend', 'Work'],
        recognitionKeywords: ['developer', 'flutter'],
      );

      expect(contact.id, contactId);
      expect(contact.firstName, 'John');
      expect(contact.lastName, 'Doe');
      expect(contact.tags, containsAll(['Friend', 'Work']));
      expect(contact.recognitionKeywords, contains('flutter'));
    });

    test('fullName returns correct combinations', () {
      final c1 = Contact(id: '1', firstName: 'John', lastName: 'Doe');
      expect(c1.fullName, 'John Doe');

      final c2 = Contact(
          id: '2', firstName: 'Jane', middleName: 'Marie', lastName: 'Smith');
      expect(c2.fullName, 'Jane Marie Smith');

      final c3 = Contact(id: '3', firstName: 'Cher');
      expect(c3.fullName, 'Cher');

      final c4 = Contact(
          id: '4',
          firstName: '',
          nickname:
              'JDoe'); // Edge case if firstName is empty but required in type system?
      // In constructor firstName is required String.
      // But let's check if we pass empty string.
      final c5 = Contact(id: '5', firstName: '', nickname: 'The Boss');
      expect(c5.fullName, 'The Boss');
    });

    test('copyWith updates fields correctly', () {
      final original = Contact(
        id: '1',
        firstName: 'John',
        lastName: 'Doe',
        tags: ['A'],
      );

      final updated = original.copyWith(
        firstName: 'Johnny',
        tags: ['A', 'B'],
      );

      expect(updated.id, original.id); // Should not change
      expect(updated.firstName, 'Johnny');
      expect(updated.lastName, 'Doe'); // Should remain
      expect(updated.tags, ['A', 'B']);
    });

    group('serialization', () {
      test('toMap and fromMap roundtrip', () {
        final original = Contact(
          id: '1',
          firstName: 'John',
          middleName: 'Q',
          lastName: 'Public',
          nickname: 'JQ',
          location: 'New York',
          firstMeetingNotes: 'Met at a conference',
          tags: ['network'],
          recognitionKeywords: ['tall', 'glasses'],
          recognitionPhotoUris: ['http://example.com/photo.jpg'],
          recognitionReminders: ['birthday'],
          interactions: [
            Interaction(
              id: 101,
              occurredAt: DateTime(2023, 1, 1),
              summary: 'Intro',
              medium: 'face_to_face',
            ),
          ],
          prayerRequests: [
            PrayerRequest(
              id: 201,
              contactId: '1',
              description: 'Health',
              status: PrayerRequestStatus.pending,
              requestedAt: DateTime(2023, 1, 2),
            ),
          ],
        );

        final map = original.toMap();
        final reconstructed = Contact.fromMap(map);

        expect(reconstructed.id, original.id);
        expect(reconstructed.firstName, original.firstName);
        expect(reconstructed.lastName, original.lastName);
        expect(reconstructed.interactions.length, 1);
        expect(reconstructed.interactions.first.summary, 'Intro');
        expect(reconstructed.prayerRequests.length, 1);
        expect(reconstructed.prayerRequests.first.description, 'Health');
        expect(reconstructed.tags, original.tags);
      });

      test('fromMap parses legacy string lists (JSON encoded strings)', () {
        final map = {
          'id': '1',
          'firstName': 'Test',
          'recognitionKeywords': '["smart", "funny"]', // JSON string
          'recognitionPhotoUris': '["img1"]',
          'recognitionReminders': '["rem1"]',
        };

        final contact = Contact.fromMap(map);
        expect(contact.recognitionKeywords, ['smart', 'funny']);
        expect(contact.recognitionPhotoUris, ['img1']);
      });

      test('fromMap parses legacy string lists (comma separated strings)', () {
        final map = {
          'id': '1',
          'firstName': 'Test',
          'recognitionKeywords': 'smart, funny', // Comma separated
        };

        final contact = Contact.fromMap(map);
        expect(contact.recognitionKeywords, ['smart', 'funny']);
      });

      test('fromMap handles null lists by using defaults', () {
        final map = {
          'id': '1',
          'firstName': 'Test',
          // lists missing
        };
        final contact = Contact.fromMap(map);
        expect(contact.tags, isEmpty);
        expect(contact.recognitionKeywords, isEmpty);
        expect(contact.interactions, isEmpty);
      });
    });
  });
}
