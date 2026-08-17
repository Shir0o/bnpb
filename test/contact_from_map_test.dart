import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/contact_stage.dart';
import 'package:bnpb/models/interaction.dart';

void main() {
  test('fromMap generates an id when missing', () {
    final contact = Contact.fromMap({'firstName': 'Alice'});

    expect(contact.firstName, 'Alice');
    expect(contact.id, isNotEmpty);
  });

  test('fromMap preserves provided id', () {
    final contact = Contact.fromMap({'id': 'contact-123', 'firstName': 'Bob'});

    expect(contact.firstName, 'Bob');
    expect(contact.id, 'contact-123');
  });

  test('stage round-trips through serialization', () {
    final contact = Contact.fromMap({
      'id': 'c1',
      'firstName': 'Cara',
      'stage': 'Group meeting',
    });

    expect(contact.stage, 'Group meeting');
    expect(contact.resolvedStage, ContactStage.groupMeeting);

    final restored = Contact.fromMap(contact.toMap());
    expect(restored.stage, 'Group meeting');
  });

  test('resolvedStage falls back to a default derived from interactions', () {
    final contact = Contact(
      id: 'c1',
      firstName: 'Dan',
      interactions: [
        for (var i = 0; i < 5; i++)
          Interaction(
            occurredAt: DateTime(2026, 8, 2 + i),
            summary: 'Chat',
            medium: 'Call',
          ),
      ],
    );

    expect(contact.stage, isNull);
    expect(contact.resolvedStage, ContactStage.regularContact);
  });
}
