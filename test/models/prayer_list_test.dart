import 'package:bnpb/models/prayer_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrayerList Model', () {
    test('should have default updatedAt and deletedAt is null', () {
      final list = PrayerList.create(name: 'Test List');
      expect(list.updatedAt, isNotNull);
      expect(
        list.updatedAt.isBefore(DateTime.now().add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(list.deletedAt, isNull);
    });

    test('should serialize and deserialize correctly', () {
      final now = DateTime.now();
      final list = PrayerList(
        id: '1',
        name: 'Test List',
        updatedAt: now,
        deletedAt: now.add(const Duration(hours: 1)),
      );

      final map = list.toMap();
      expect(map['updatedAt'], now.toIso8601String());
      expect(
        map['deletedAt'],
        now.add(const Duration(hours: 1)).toIso8601String(),
      );

      final restored = PrayerList.fromMap(map);
      expect(restored.updatedAt, now);
      expect(restored.deletedAt, now.add(const Duration(hours: 1)));
    });

    test(
      'should use DateTime.now() if updatedAt is missing in fromMap (legacy)',
      () {
        final map = {'id': '1', 'name': 'Legacy List'};
        final list = PrayerList.fromMap(map);
        expect(list.updatedAt, isNotNull);
      },
    );
  });
}
