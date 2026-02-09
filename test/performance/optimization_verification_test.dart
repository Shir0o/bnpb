import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';

void main() {
  test('Contact.fromMap avoids copy when tags is List<String>', () {
    final tags = ['tag1', 'tag2'];
    final map = {
      'id': '123',
      'firstName': 'Test',
      'tags': tags,
    };

    final contact = Contact.fromMap(map);

    // Identity check: The list instance should be exactly the same
    expect(identical(contact.tags, tags), isTrue, reason: 'Tags list should be passed by reference');
  });

  test('Interaction.fromMap avoids copy when participantIds is List<String>', () {
    final participants = ['p1', 'p2'];
    final map = {
      'id': 1,
      'occurredAt': DateTime.now().toIso8601String(),
      'summary': 'Test',
      'medium': 'call',
      'participantIds': participants,
    };

    final interaction = Interaction.fromMap(map);

    // Identity check
    expect(identical(interaction.participantIds, participants), isTrue, reason: 'ParticipantIds list should be passed by reference');
  });

  test('Contact.fromMap handles legacy List<dynamic> correctly', () {
    final tags = ['tag1', 'tag2'];
    // Simulate JSON decode result which gives List<dynamic>
    final dynamicTags = List<dynamic>.from(tags);
    final map = {
      'id': '123',
      'firstName': 'Test',
      'tags': dynamicTags,
    };

    final contact = Contact.fromMap(map);

    expect(contact.tags, equals(tags));
    // Identity check: Should be different because it had to copy
    expect(identical(contact.tags, dynamicTags), isFalse);
  });
}
