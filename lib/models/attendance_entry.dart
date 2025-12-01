/// Attendance status for a contact within a session.
enum AttendanceStatus { present, absent }

/// Records whether a contact was present for a specific [AttendanceSession].
class AttendanceEntry {
  const AttendanceEntry({
    this.id,
    required this.sessionId,
    required this.contactId,
    required this.status,
  });

  final int? id;
  final int sessionId;
  final String contactId;
  final AttendanceStatus status;

  AttendanceEntry copyWith({
    int? id,
    int? sessionId,
    String? contactId,
    AttendanceStatus? status,
  }) {
    return AttendanceEntry(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      contactId: contactId ?? this.contactId,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = <String, dynamic>{
      'sessionId': sessionId,
      'contactId': contactId,
      'status': status.name,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  static AttendanceEntry fromMap(Map<String, dynamic> map) {
    final statusValue = map['status'] as String?;
    return AttendanceEntry(
      id: map['id'] as int?,
      sessionId: map['sessionId'] as int,
      contactId: map['contactId'] as String,
      status: AttendanceStatus.values.firstWhere(
        (value) => value.name == statusValue,
        orElse: () => AttendanceStatus.absent,
      ),
    );
  }
}
