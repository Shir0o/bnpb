import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/notification_preference.dart';

void main() {
  group('NotificationPreference', () {
    test('ReminderChannel properties return correct defaults', () {
      expect(ReminderChannel.followUp.label, isNotEmpty);
      expect(
          ReminderChannel.followUp.defaultLeadTime, const Duration(hours: 1));
      expect(ReminderChannel.weeklyReview.defaultLeadTime, Duration.zero);
    });

    test('serialization works correctly', () {
      final pref = NotificationPreference(
        id: 1,
        scopeType: NotificationScopeType.contact,
        scopeId: 'c1',
        channel: ReminderChannel.followUp,
        enabled: true,
        leadTime: const Duration(minutes: 30),
      );

      final map = pref.toMap();
      expect(map['id'], 1);
      expect(map['scopeType'], 'contact');
      expect(map['channel'], 'followUp');
      expect(map['leadTimeMinutes'], 30);
      expect(map['enabled'], 1);

      final restored = NotificationPreference.fromMap(map);
      expect(restored.id, 1);
      expect(restored.scopeType, NotificationScopeType.contact);
      expect(restored.leadTime, const Duration(minutes: 30));
    });

    test('defaults to global if scope invalid', () {
      final map = {
        'scopeType': 'invalid',
        'scopeId': 'x',
        'channel': 'followUp',
      };
      final pref = NotificationPreference.fromMap(map);
      expect(pref.scopeType, NotificationScopeType.global);
    });
  });
}
