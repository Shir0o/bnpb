import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/attendance_session.dart';
import 'package:bnpb/models/attendance_entry.dart';
import 'package:bnpb/repositories/analytics_repository.dart';
import 'mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  List<Contact> contacts = [];
  List<AttendanceSession> sessions = [];
  List<AttendanceEntry> entries = [];

  @override
  Future<List<Contact>> getContacts({String? contactId}) async {
    if (contactId != null) {
      return contacts.where((c) => c.id == contactId).toList();
    }
    return contacts;
  }

  @override
  Future<List<AttendanceSession>> getAttendanceSessions({int? sessionId}) async {
    return sessions;
  }

  @override
  Future<List<AttendanceEntry>> getAttendanceEntries(int sessionId) async {
    return entries.where((e) => e.sessionId == sessionId).toList();
  }
}

void main() {
  group('AnalyticsRepository', () {
    late AnalyticsRepository repository;
    late _TestDBHelper dbHelper;

    setUp(() {
      dbHelper = _TestDBHelper();
      repository = AnalyticsRepository(dbHelper: dbHelper);
    });

    test('buildSummary aggregates interactions correctly', () async {
      final now = DateTime.now();
      final c1 = Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 1)),
            summary: 'Chat',
            medium: 'phone',
            durationMinutes: 30,
            category: 'Work',
          ),
          Interaction(
            occurredAt: now.subtract(const Duration(days: 2)),
            summary: 'Coffee',
            medium: 'in_person',
            durationMinutes: 60,
            category: 'Social',
          ),
        ],
      );
      dbHelper.contacts.add(c1);

      final summary = await repository.buildSummary();
      
      expect(summary.totalMinutes, 90);
      expect(summary.totalInteractions, 2);
      
      // Category breakdown
      expect(summary.categoryBreakdown.length, 2);
      expect(
        summary.categoryBreakdown.any((e) => e.category == 'Work' && e.totalMinutes == 30),
        isTrue,
      );
    });

    test('buildSummary calculates attendance rates', () async {
      final session = AttendanceSession(
        id: 1,
        title: 'Session',
        sessionDate: DateTime.now(),
      );
      dbHelper.sessions.add(session);
      dbHelper.contacts.addAll([
        Contact(id: 'c1', firstName: 'A'),
        Contact(id: 'c2', firstName: 'B'),
      ]);
      dbHelper.entries.addAll([
        AttendanceEntry(sessionId: 1, contactId: 'c1', status: AttendanceStatus.present),
        AttendanceEntry(sessionId: 1, contactId: 'c2', status: AttendanceStatus.absent),
      ]);

      final summary = await repository.buildSummary();
      
      expect(summary.sessionAttendance.length, 1);
      final snapshot = summary.sessionAttendance.first;
      expect(snapshot.presentCount, 1);
      expect(snapshot.totalCount, 2);
      expect(snapshot.attendanceRate, 0.5);
    });

    test('buildSummary respects date range', () async {
      final now = DateTime.now();
      final c1 = Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 10)), // Outside
            summary: 'Old',
            medium: 'phone',
            durationMinutes: 60,
          ),
          Interaction(
            occurredAt: now.subtract(const Duration(days: 1)), // Inside
            summary: 'New',
            medium: 'phone',
            durationMinutes: 30,
          ),
        ],
      );
      dbHelper.contacts.add(c1);

      final summary = await repository.buildSummary(
        rangeStart: now.subtract(const Duration(days: 5)),
      );

      expect(summary.totalMinutes, 30);
      expect(summary.totalInteractions, 1);
    });
  });
}
