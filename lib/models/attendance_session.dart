/// Represents a gathering or event where contact attendance is tracked.
class AttendanceSession {
  const AttendanceSession({
    this.id,
    required this.title,
    required this.sessionDate,
    this.location,
  });

  final int? id;
  final String title;
  final DateTime sessionDate;
  final String? location;

  AttendanceSession copyWith({
    int? id,
    String? title,
    DateTime? sessionDate,
    String? location,
  }) {
    return AttendanceSession(
      id: id ?? this.id,
      title: title ?? this.title,
      sessionDate: sessionDate ?? this.sessionDate,
      location: location ?? this.location,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = <String, dynamic>{
      'title': title,
      'sessionDate': sessionDate.toIso8601String(),
      'location': location,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  static AttendanceSession fromMap(Map<String, dynamic> map) {
    return AttendanceSession(
      id: map['id'] as int?,
      title: map['title'] as String,
      sessionDate: DateTime.parse(map['sessionDate'] as String),
      location: map['location'] as String?,
    );
  }
}
