class HistoryEntry {
  final DateTime date; // Date of the history entry
  final String detail; // Detail of the history entry

  HistoryEntry({
    required this.date,
    required this.detail,
  });

  // Converts a HistoryEntry object into a Map for storage or serialization
  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'detail': detail,
    };
  }

  // Creates a HistoryEntry object from a Map (e.g., reading from a database)
  static HistoryEntry fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      date: DateTime.parse(map['date']),
      detail: map['detail'],
    );
  }
}

class Contact {
  final String id; // Unique identifier for the contact
  final String firstName; // First name of the contact
  final String middleName; // Middle name of the contact (optional)
  final String lastName; // Last name of the contact
  final String? grade; // Grade, if the contact is a student (optional)
  final String? occupation; // Occupation, if the contact is working (optional)
  final List<HistoryEntry> history; // List of history entries for the contact

  Contact({
    required this.id,
    required this.firstName,
    this.middleName = '', // Default middle name is empty
    required this.lastName,
    this.grade,
    this.occupation,
    List<HistoryEntry>? history, // Default to an empty list if not provided
  }) : history = history ?? [];

  Contact copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? grade,
    String? occupation,
    List<HistoryEntry>? history,
  }) {
    return Contact(
      id: this.id,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      grade: grade ?? this.grade,
      occupation: occupation ?? this.occupation,
      history: history ?? this.history,
    );
  }

  // Converts a Contact object into a Map for storage or serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'grade': grade,
      'occupation': occupation,
      'history': history.map((entry) => entry.toMap()).toList(),
    };
  }

  // Creates a Contact object from a Map (e.g., reading from a database)
  static Contact fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'],
      firstName: map['firstName'],
      middleName: map['middleName'] ?? '',
      lastName: map['lastName'],
      grade: map['grade'],
      occupation: map['occupation'],
      history: (map['history'] as List<dynamic>?)
          ?.map((entry) => HistoryEntry.fromMap(entry))
          .toList() ??
          [],
    );
  }

  // Combines first, middle, and last names into a single full name
  String get fullName {
    return [firstName, middleName, lastName].where((name) => name.isNotEmpty).join(' ');
  }
}