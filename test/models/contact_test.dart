import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/relationship.dart';

void main() {
  group('Contact', () {
    const contactId = 'contact-123';

    test('props are correctly assigned via constructor', () {
      final contact = Contact(
        id: contactId,
        firstName: 'John',
        lastName: 'Doe',
      );

      expect(contact.id, contactId);
      expect(contact.firstName, 'John');
      expect(contact.lastName, 'Doe');
    });

    test('fullName returns correct combinations', () {
      final c1 = Contact(id: '1', firstName: 'John', lastName: 'Doe');
      expect(c1.fullName, 'John Doe');

      final c2 = Contact(
        id: '2',
        firstName: 'Jane',
        middleName: 'Marie',
        lastName: 'Smith',
      );
      expect(c2.fullName, 'Jane Marie Smith');

      final c3 = Contact(id: '3', firstName: 'Cher');
      expect(c3.fullName, 'Cher');

      final c5 = Contact(id: '5', firstName: '', nickname: 'The Boss');
      expect(c5.fullName, 'The Boss');
    });

    test('copyWith updates fields correctly', () {
      final original = Contact(id: '1', firstName: 'John', lastName: 'Doe');

      final updated = original.copyWith(firstName: 'Johnny');

      expect(updated.id, original.id);
      expect(updated.firstName, 'Johnny');
      expect(updated.lastName, 'Doe');
    });

    test('displayName and initials use fallbacks for unnamed contacts', () {
      final contact = Contact(id: '1', firstName: '');

      expect(contact.displayName, 'Unknown');
      expect(contact.initials, '?');
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
              participantIds: ['1'],
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
      });

      test('fromMap handles null lists by using defaults', () {
        final map = {'id': '1', 'firstName': 'Test'};
        final contact = Contact.fromMap(map);
        expect(contact.interactions, isEmpty);
      });

      test('toMap and fromMap preserve relationships', () {
        final original = Contact(
          id: '1',
          firstName: 'John',
          relationships: const [
            Relationship(
              id: 301,
              sourceContactId: '1',
              targetContactId: '2',
              type: 'Mentor',
              notes: 'Meets monthly',
            ),
          ],
        );

        final reconstructed = Contact.fromMap(original.toMap());

        expect(reconstructed.relationships, hasLength(1));
        expect(reconstructed.relationships.first.id, 301);
        expect(reconstructed.relationships.first.sourceContactId, '1');
        expect(reconstructed.relationships.first.targetContactId, '2');
        expect(reconstructed.relationships.first.type, 'Mentor');
        expect(reconstructed.relationships.first.notes, 'Meets monthly');
      });
    });
  });
}
