import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/attendance_session.dart';

void main() {
  group('AttendanceSession', () {
    test('copyWith creates updated instance', () {
      final date = DateTime(2023, 1, 1);
      final session = AttendanceSession(
        title: 'Sunday Service',
        sessionDate: date,
        location: 'Main Hall',
      );
      final updated = session.copyWith(title: 'Updated Service');
      expect(updated.title, 'Updated Service');
      expect(updated.sessionDate, date);
      expect(updated.location, 'Main Hall');
    });

    test('toMap returns correct map', () {
      final date = DateTime(2023, 1, 1, 10, 0, 0);
      final session = AttendanceSession(
        id: 5,
        title: 'Sunday Service',
        sessionDate: date,
        location: 'Main Hall',
      );
      final map = session.toMap();
      expect(map, {
        'id': 5,
        'title': 'Sunday Service',
        'sessionDate': date.toIso8601String(),
        'location': 'Main Hall',
      });
    });

    test('fromMap parses correct map', () {
      final date = DateTime(2023, 1, 1, 10, 0, 0);
      final map = {
        'id': 5,
        'title': 'Sunday Service',
        'sessionDate': date.toIso8601String(),
        'location': 'Main Hall',
      };
      final session = AttendanceSession.fromMap(map);
      expect(session.id, 5);
      expect(session.title, 'Sunday Service');
      expect(session.sessionDate, date);
      expect(session.location, 'Main Hall');
    });
  });
}
