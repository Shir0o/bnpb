import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/attendance_entry.dart';
import 'package:bnpb/models/attendance_session.dart';
import 'package:bnpb/repositories/attendance_repository.dart';
import 'mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  List<AttendanceSession> sessions = [];
  List<AttendanceEntry> entries = [];
  int _idCounter = 1;

  @override
  Future<AttendanceSession> insertAttendanceSession(AttendanceSession session) async {
    final newSession = session.copyWith(id: _idCounter++);
    sessions.add(newSession);
    return newSession;
  }

  @override
  Future<void> deleteAttendanceSession(int sessionId) async {
    sessions.removeWhere((s) => s.id == sessionId);
    entries.removeWhere((e) => e.sessionId == sessionId);
  }

  @override
  Future<AttendanceEntry> upsertAttendanceEntry(AttendanceEntry entry) async {
    final existing = entries.indexWhere(
      (e) => e.sessionId == entry.sessionId && e.contactId == entry.contactId,
    );
    final newEntry = entry.copyWith(id: _idCounter++);
    if (existing >= 0) {
      entries[existing] = newEntry;
    } else {
      entries.add(newEntry);
    }
    return newEntry;
  }

  @override
  Future<List<AttendanceSession>> getAttendanceSessions({int? sessionId}) async {
    if (sessionId != null) {
      return sessions.where((s) => s.id == sessionId).toList();
    }
    return sessions;
  }

  @override
  Future<List<AttendanceEntry>> getAttendanceEntries(int sessionId) async {
    return entries.where((e) => e.sessionId == sessionId).toList();
  }
}

void main() {
  group('AttendanceRepository', () {
    late AttendanceRepository repository;
    late _TestDBHelper dbHelper;

    setUp(() {
      dbHelper = _TestDBHelper();
      repository = AttendanceRepository(dbHelper: dbHelper);
    });

    test('createSession inserts session', () async {
      final session = await repository.createSession(
        title: 'Weekly',
        sessionDate: DateTime(2023, 1, 1),
        location: 'Hall',
      );
      expect(session.id, isNotNull);
      expect(session.title, 'Weekly');
      expect(dbHelper.sessions.length, 1);
    });

    test('deleteSession removes session and entries', () async {
      final session = await repository.createSession(
        title: 'Delete Me',
        sessionDate: DateTime.now(),
      );
      await repository.markAttendance(
        sessionId: session.id!,
        contactId: 'c1',
        status: AttendanceStatus.present,
      );
      
      await repository.deleteSession(session.id!);
      
      expect(dbHelper.sessions, isEmpty);
      expect(dbHelper.entries, isEmpty);
    });

    test('markAttendance updates entry', () async {
      final entry = await repository.markAttendance(
        sessionId: 1,
        contactId: 'c1',
        status: AttendanceStatus.absent,
      );
      expect(entry.status, AttendanceStatus.absent);
      expect(dbHelper.entries.length, 1);

      // Update
      await repository.markAttendance(
        sessionId: 1,
        contactId: 'c1',
        status: AttendanceStatus.present,
      );
      expect(dbHelper.entries.length, 1);
      expect(dbHelper.entries.first.status, AttendanceStatus.present);
    });

    test('getAttendanceSessions returns sessions', () async {
      await repository.createSession(title: 'S1', sessionDate: DateTime.now());
      await repository.createSession(title: 'S2', sessionDate: DateTime.now());
      
      final sessions = await repository.getAttendanceSessions();
      expect(sessions.length, 2);
    });

    test('getEntriesForSession returns filtered entries', () async {
      await repository.markAttendance(
        sessionId: 1, 
        contactId: 'c1', 
        status: AttendanceStatus.present,
      );
      await repository.markAttendance(
        sessionId: 2, 
        contactId: 'c2', 
        status: AttendanceStatus.absent,
      );

      final entries = await repository.getEntriesForSession(1);
      expect(entries.length, 1);
      expect(entries.first.contactId, 'c1');
    });
  });
}
