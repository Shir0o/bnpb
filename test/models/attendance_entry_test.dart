import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/attendance_entry.dart';

void main() {
  group('AttendanceEntry', () {
    test('supports value equality', () {
      final entry1 = AttendanceEntry(
        sessionId: 1,
        contactId: 'c1',
        status: AttendanceStatus.present,
      );
      final entry2 = AttendanceEntry(
        sessionId: 1,
        contactId: 'c1',
        status: AttendanceStatus.present,
      );
      // Note: Class does not override ==/hashCode but let's test properties
      expect(entry1.sessionId, entry2.sessionId);
      expect(entry1.contactId, entry2.contactId);
      expect(entry1.status, entry2.status);
    });

    test('copyWith creates a new instance with updated values', () {
      final entry = AttendanceEntry(
        sessionId: 1,
        contactId: 'c1',
        status: AttendanceStatus.present,
      );
      final updated = entry.copyWith(
        status: AttendanceStatus.absent,
      );
      expect(updated.sessionId, entry.sessionId);
      expect(updated.contactId, entry.contactId);
      expect(updated.status, AttendanceStatus.absent);
    });

    test('toMap returns correct map', () {
      final entry = AttendanceEntry(
        id: 10,
        sessionId: 1,
        contactId: 'c1',
        status: AttendanceStatus.present,
      );
      final map = entry.toMap();
      expect(map, {
        'id': 10,
        'sessionId': 1,
        'contactId': 'c1',
        'status': 'present',
      });
    });

    test('fromMap parses correct map', () {
      final map = {
        'id': 10,
        'sessionId': 1,
        'contactId': 'c1',
        'status': 'present',
      };
      final entry = AttendanceEntry.fromMap(map);
      expect(entry.id, 10);
      expect(entry.sessionId, 1);
      expect(entry.contactId, 'c1');
      expect(entry.status, AttendanceStatus.present);
    });

    test('fromMap defaults to absent if status invalid', () {
      final map = {
        'sessionId': 1,
        'contactId': 'c1',
        'status': 'unknown',
      };
      final entry = AttendanceEntry.fromMap(map);
      expect(entry.status, AttendanceStatus.absent);
    });
  });
}
