class Contact {
  final String id; // Unique identifier for the contact
  final String firstName; // First name of the contact
  final String middleName; // Middle name of the contact (optional)
  final String lastName; // Last name of the contact
  final String? grade; // Grade, if the contact is a student (optional)
  final String? occupation; // Occupation, if the contact is working (optional)
  final List<String> history; // List of history entries for the contact
  final Map<String, String> relationships; // Relationships with other contacts

  Contact({
    required this.id,
    required this.firstName,
    this.middleName = '', // Default middle name is empty
    required this.lastName,
    this.grade = null, // Default grade is null
    this.occupation,
    List<String>? history, // Default to an empty list if not provided
    Map<String, String>? relationships, // Default to an empty map if not provided
  })  : history = history ?? [],
        relationships = relationships ?? {};

  // Converts a Contact object into a Map for storage or serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'grade': grade,
      'occupation': occupation,
      'history': history,
      'relationships': relationships,
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
      history: List<String>.from(map['history'] ?? []),
      relationships: Map<String, String>.from(map['relationships'] ?? {}),
    );
  }

  // Combines first, middle, and last names into a single full name
  String get fullName {
    return [firstName, middleName, lastName].where((name) => name.isNotEmpty).join(' ');
  }
}
