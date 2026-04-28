import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ExportService', () {
    test('buildExportPayload constructs correct JSON structure', () {
      final contacts = [
        Contact(
          id: 'c1',
          firstName: 'Alice',
          lastName: 'Smith',
          interactions: [],
          tags: ['Friend'],
        ),
      ];
      final fields = ['firstName', 'lastName', 'tags'];

      final service = ExportService();
      final payload = service.buildExportPayload(contacts, fields);

      expect(payload.length, 1);
      final item = payload.first;
      expect(item['firstName'], 'Alice');
      expect(item['lastName'], 'Smith');
      expect(item['tags'], ['Friend']);
      expect(item.containsKey('nickname'), true); // Always included now
      expect(item['id'], 'c1'); // Always included
    });

    test('export payload contains interactions with attachment maps', () {
      final interaction = Interaction(
        id: 1,
        occurredAt: DateTime.utc(2024, 1, 1),
        summary: 'Coffee catch-up',
        medium: 'In person',
        location: 'Neighborhood cafe',
        attachments: const [
          AttachmentReference(
            uri: 'file:///notes',
            source: AttachmentSource.local,
            label: 'Meeting notes',
          ),
        ],
        markForPrayer: true,
        followUpAt: DateTime.utc(2024, 1, 15),
        durationMinutes: 45,
        notes: 'Check-in',
      );

      final contact = Contact(
        id: 'contact-1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        interactions: [interaction],
      );

      final payload = ExportService().buildExportPayload(
        [contact],
        const ['firstName', 'lastName'],
      );

      expect(payload, hasLength(1));
      final contactJson = payload.first;
      expect(contactJson['firstName'], 'Ada');
      expect(contactJson['lastName'], 'Lovelace');
      expect(contactJson['interactions'], isA<List>());

      final interactions = contactJson['interactions'] as List<dynamic>;
      expect(interactions, hasLength(1));

      final interactionJson = interactions.first as Map<String, dynamic>;
      expect(interactionJson['id'], 1);
      expect(interactionJson['attachments'], isA<List>());

      final attachments = interactionJson['attachments'] as List<dynamic>;
      expect(attachments, hasLength(1));

      final attachment = attachments.first as Map<String, dynamic>;
      expect(attachment['uri'], 'file:///notes');
      expect(attachment['source'], AttachmentSource.local.name);
      expect(attachment['label'], 'Meeting notes');
      expect(interactionJson['markForPrayer'], isTrue);
      expect(interactionJson['followUpAt'], '2024-01-15T00:00:00.000Z');
      expect(interactionJson['durationMinutes'], 45);
      expect(interactionJson['notes'], 'Check-in');
    });

    test(
      'buildFullExportPayload de-duplicates shared data and includes participants',
      () async {
        final now = DateTime.now().toUtc();
        final interaction = Interaction(
          id: 1,
          occurredAt: now,
          summary: 'Shared Interaction',
          medium: 'In person',
          participantIds: ['c1', 'c2'],
        );

        final prayer = PrayerRequest(
          id: 10,
          participantIds: ['c1', 'c2'],
          description: 'Shared Prayer',
          status: PrayerRequestStatus.pending,
          requestedAt: now,
          interactionId: 1,
        );

        final contact1 = Contact(
          id: 'c1',
          firstName: 'Alice',
          interactions: [interaction],
          prayerRequests: [prayer],
        );

        final contact2 = Contact(
          id: 'c2',
          firstName: 'Bob',
          interactions: [interaction],
          prayerRequests: [prayer],
        );

        final service = ExportService();
        final payload = await service.buildFullExportPayload(
          [contact1, contact2],
          ['firstName'],
        );

        expect(payload['version'], 2);
        expect(payload['contacts'], hasLength(2));
        expect(payload['interactions'], hasLength(1)); // De-duplicated
        expect(payload['prayerRequests'], hasLength(1)); // De-duplicated

        final interactionJson = (payload['interactions'] as List).first;
        expect(interactionJson['summary'], 'Shared Interaction');
        expect(interactionJson['participantIds'], containsAll(['c1', 'c2']));

        final prayerJson = (payload['prayerRequests'] as List).first;
        expect(prayerJson['description'], 'Shared Prayer');
        expect(prayerJson['participantIds'], containsAll(['c1', 'c2']));
        expect(prayerJson['interactionSyncId'], interaction.syncId);
      },
    );
    group('buildFullExportPayload', () {
      test(
        'correctly de-duplicates interactions and prayer requests',
        () async {
          final interaction = Interaction(
            id: 1,
            occurredAt: DateTime.now(),
            summary: 'Shared Interaction',
            medium: 'face_to_face',
            participantIds: ['contact-1', 'contact-2'],
          );

          final prayerRequest = PrayerRequest(
            id: 1,
            participantIds: ['contact-1', 'contact-2'],
            description: 'Shared Prayer',
            status: PrayerRequestStatus.pending,
            requestedAt: DateTime.now(),
            interactionId: 1,
          );

          final contact1 = Contact(
            id: 'contact-1',
            firstName: 'Contact',
            lastName: 'One',
            interactions: [interaction],
            prayerRequests: [prayerRequest],
          );

          final contact2 = Contact(
            id: 'contact-2',
            firstName: 'Contact',
            lastName: 'Two',
            interactions: [interaction],
            prayerRequests: [prayerRequest],
          );

          final payload = await ExportService().buildFullExportPayload([
            contact1,
            contact2,
          ], []);

          expect(payload['interactions'], hasLength(1));
          expect(payload['prayerRequests'], hasLength(1));
          expect(
            payload['prayerRequests'][0]['interactionSyncId'],
            interaction.syncId,
          );
        },
      );

      test('includes prayerLists in the payload', () async {
        final contact = Contact(id: 'c1', firstName: 'Alice');
        final prayerList = PrayerList(
          id: 'l1',
          name: 'Morning Prayer',
          contactIds: ['c1'],
        );

        final payload = await ExportService().buildFullExportPayload(
          [contact],
          ['firstName'],
          prayerLists: [prayerList],
        );

        expect(payload['prayerLists'], hasLength(1));
        final listJson = (payload['prayerLists'] as List).first;
        expect(listJson['id'], 'l1');
        expect(listJson['name'], 'Morning Prayer');
        expect(listJson['contactIds'], ['c1']);
      });
    });
  });
}
