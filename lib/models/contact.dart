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

  // Creates a HistoryEntry object from a Map
  static HistoryEntry fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      date: DateTime.parse(map['date']),
      detail: map['detail'],
    );
  }
}

class Contact {
  final String id;            // Unique identifier for the contact
  final String firstName;     // First name of the contact
  final String middleName;    // Middle name of the contact (optional)
  final String? lastName;     // Last name of the contact (optional)
  final String? location;     // Location of the contact (optional)
  final List<HistoryEntry> history; // List of history entries for the contact

  Contact({
    required this.id,
    required this.firstName,
    this.middleName = '', // Default middle name is empty
    this.lastName,        // Last name is now optional
    this.location, // Location field added
    List<HistoryEntry>? history,
  }) : history = history ?? [];

  Contact copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? location, // Add location to copyWith
    List<HistoryEntry>? history,
  }) {
    return Contact(
      id: id,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName, // Handle optional lastName
      location: location ?? this.location, // Update location
      history: history ?? this.history,
    );
  }

  // Converts a Contact object into a Map for storage or serialization.
  // Notice: We keep `history` as a List of Maps here.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName, // Handle optional lastName
      'location': location, // Add location to toMap
      'history': history.map((entry) => entry.toMap()).toList(),
    };
  }

  // Creates a Contact object from a Map that already has `history` as a List of Maps.
  static Contact fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'],
      firstName: map['firstName'],
      middleName: map['middleName'] ?? '',
      lastName: map['lastName'], // Retrieve optional lastName
      location: map['location'], // Retrieve location from map
      history: (map['history'] as List<dynamic>?)
          ?.map((entry) => HistoryEntry.fromMap(entry))
          .toList() ??
          [],
    );
  }

  // Combines first, middle, and last names into a single full name
  String get fullName {
    return [firstName, middleName, if (lastName != null) lastName!]
        .where((name) => name.isNotEmpty)
        .join(' ');
  }
}