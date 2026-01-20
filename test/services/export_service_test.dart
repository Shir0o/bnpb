import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/export_service.dart';

void main() {
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
        // contactId removed as it's no longer in the model
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
        category: 'Check-in',
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
      // DateTime toIso8601String ends with Z only if UTC and properly formatted?
      // contact.interactions.first.followUpAt is UTC.
      // toIso8601String() usually returns "2024-01-15T00:00:00.000Z"
      expect(interactionJson['followUpAt'], '2024-01-15T00:00:00.000Z');
      expect(interactionJson['durationMinutes'], 45);
      expect(interactionJson['category'], 'Check-in');
    });
  });
}
