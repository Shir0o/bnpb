import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/interaction.dart';

void main() {
  group('Interaction', () {
    test('parses correct map with all fields', () {
      final date = DateTime(2023, 1, 1, 12, 0, 0);
      final followUp = date.add(const Duration(days: 1));
      final map = {
        'id': 1,
        'occurredAt': date.toIso8601String(),
        'summary': 'Lunch',
        'medium': 'in_person',
        'location': 'Cafe',
        'markForPrayer': 1,
        'followUpAt': followUp.toIso8601String(),
        'durationMinutes': 60,
        'category': 'Social',
        'participantIds': ['p1', 'p2'],
        'attachments': [
          {'uri': 'file.jpg', 'source': 'local', 'label': 'Photo'},
        ],
      };

      final interaction = Interaction.fromMap(map);
      expect(interaction.id, 1);
      expect(interaction.occurredAt, date);
      expect(interaction.markForPrayer, true);
      expect(interaction.durationMinutes, 60);
      expect(interaction.participantIds, ['p1', 'p2']);
      expect(interaction.attachments.length, 1);
      expect(interaction.attachments.first.uri, 'file.jpg');
    });

    test('toJson encodes attachments correctly', () {
      final interaction = Interaction(
        occurredAt: DateTime(2023, 1, 1),
        summary: 'Test',
        medium: 'phone',
        attachments: [
          AttachmentReference(
            uri: 'http://test.com',
            source: AttachmentSource.cloud,
          ),
        ],
      );

      final map = interaction.toJson();
      final attachments = map['attachments'] as List;
      expect(attachments.length, 1);
      expect(attachments.first['uri'], 'http://test.com');
      expect(attachments.first['source'], 'cloud');
    });

    test('toMap encodes attachments as string when requested', () {
      final interaction = Interaction(
        occurredAt: DateTime(2023, 1, 1),
        summary: 'Test',
        medium: 'phone',
        attachments: [
          AttachmentReference(uri: 'file.txt', source: AttachmentSource.local),
        ],
      );

      final map = interaction.toMap(encodeAttachments: true);
      expect(map['attachments'], isA<String>());
      expect(map['attachments'], contains('file.txt'));
    });

    test('parses diverse markForPrayer formats', () {
      expect(InteractioHelper.parseMarkForPrayer(true), true);
      expect(InteractioHelper.parseMarkForPrayer(false), false);
      expect(InteractioHelper.parseMarkForPrayer(1), true);
      expect(InteractioHelper.parseMarkForPrayer(0), false);
      expect(InteractioHelper.parseMarkForPrayer('true'), true);
      expect(InteractioHelper.parseMarkForPrayer('false'), false);
    });
  });
}

// Expose private static method for testing if needed, but since it's private
// we rely on fromMap testing. Let's test via fromMap directly.
extension InteractioHelper on Interaction {
  static bool parseMarkForPrayer(dynamic value) {
    final map = {
      'occurredAt': DateTime.now().toIso8601String(),
      'summary': '',
      'medium': '',
      'markForPrayer': value,
    };
    return Interaction.fromMap(map).markForPrayer;
  }
}
