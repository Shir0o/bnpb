import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/export_service.dart';

void main() {
  test('export payload contains interactions with attachment maps', () {
    final interaction = Interaction(
      id: 1,
      contactId: 'contact-1',
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
      dietaryPreference: 'Vegetarian',
      interactions: [interaction],
    );

    final payload = ExportService().buildExportPayload(
      [contact],
      const ['firstName', 'lastName', 'dietaryPreference'],
    );

    expect(payload, hasLength(1));
    final contactJson = payload.first;
    expect(contactJson['firstName'], 'Ada');
    expect(contactJson['lastName'], 'Lovelace');
    expect(contactJson['dietaryPreference'], 'Vegetarian');
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
    expect(interactionJson['category'], 'Check-in');
  });
}
