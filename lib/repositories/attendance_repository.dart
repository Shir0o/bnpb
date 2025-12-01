import '../db/db_helper.dart';
import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';

/// Provides a single entry point for attendance-related persistence queries.
class AttendanceRepository {
  AttendanceRepository({DBHelper? dbHelper}) : _dbHelper = dbHelper ?? DBHelper();

  final DBHelper _dbHelper;

  /// Creates a new attendance session with the provided metadata.
  Future<AttendanceSession> createSession({
    required String title,
    required DateTime sessionDate,
    String? location,
  }) {
    final session = AttendanceSession(
      title: title,
      sessionDate: sessionDate,
      location: location,
    );
    return _dbHelper.insertAttendanceSession(session);
  }

  /// Removes a session and its recorded entries.
  Future<void> deleteSession(int sessionId) {
    return _dbHelper.deleteAttendanceSession(sessionId);
  }

  /// Marks whether [contactId] was present for the given [sessionId].
  Future<AttendanceEntry> markAttendance({
    required int sessionId,
    required String contactId,
    required AttendanceStatus status,
  }) {
    final entry = AttendanceEntry(
      sessionId: sessionId,
      contactId: contactId,
      status: status,
    );
    return _dbHelper.upsertAttendanceEntry(entry);
  }

  /// Lists all attendance sessions ordered by most recent first.
  Future<List<AttendanceSession>> getAttendanceSessions({int? sessionId}) {
    return _dbHelper.getAttendanceSessions(sessionId: sessionId);
  }

  /// Lists attendance entries for a specific session.
  Future<List<AttendanceEntry>> getEntriesForSession(int sessionId) {
    return _dbHelper.getAttendanceEntries(sessionId);
  }
}
