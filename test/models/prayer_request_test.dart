import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/prayer_request.dart';

void main() {
  group('PrayerRequest', () {
    test('status helper methods work', () {
      expect(PrayerRequestStatus.pending.label, 'Pending');
      expect(
        PrayerRequestStatusX.fromStorage('pending'),
        PrayerRequestStatus.pending,
      );
      expect(
        PrayerRequestStatusX.fromStorage('unknown'),
        PrayerRequestStatus.pending,
      );
    });

    test('serialization works correctly', () {
      final date = DateTime(2023, 1, 1);
      final req = PrayerRequest(
        id: 10,
        participantIds: ['c1'],
        description: 'Health',
        status: PrayerRequestStatus.answered,
        requestedAt: date,
        answeredAt: date.add(const Duration(days: 5)),
      );

      final map = req.toMap();
      expect(map['id'], 10);
      expect(map['status'], 'answered');
      expect(map['answeredAt'], isNotNull);
      expect(map['participantIds'], ['c1']);
      expect(map['contactId'], 'c1');

      final restored = PrayerRequest.fromMap(map);
      expect(restored.id, 10);
      expect(restored.status, PrayerRequestStatus.answered);
      expect(restored.answeredAt, date.add(const Duration(days: 5)));
      expect(restored.participantIds, ['c1']);
    });

    test('handles null optional fields and legacy contactId', () {
      final req = PrayerRequest.fromMap({
        'contactId': 'c1',
        'description': 'Test',
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
      });
      expect(req.participantIds, ['c1']);
      expect(req.answeredAt, null);
      expect(req.category, null);
    });
  });
}
