import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/relationship.dart';

void main() {
  group('Relationship', () {
    test('serialization works correctly', () {
      final rel = Relationship(
        id: 1,
        sourceContactId: 'c1',
        targetContactId: 'c2',
        type: 'Spouse',
        notes: 'Married 2020',
      );

      final map = rel.toMap();
      expect(map['id'], 1);
      expect(map['type'], 'Spouse');

      final restored = Relationship.fromMap(map);
      expect(restored.id, 1);
      expect(restored.type, 'Spouse');
      expect(restored.notes, 'Married 2020');
    });

    test('copyWith creates updated instance', () {
      final rel = Relationship(
        sourceContactId: 'c1',
        targetContactId: 'c2',
        type: 'Friend',
      );
      final updated = rel.copyWith(type: 'Colleague');
      expect(updated.type, 'Colleague');
      expect(updated.sourceContactId, 'c1');
    });
  });
}
