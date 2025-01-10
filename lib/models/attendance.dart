class Attendance {
  final String eventId; // Unique identifier for the event
  final String eventTitle; // Title of the event
  final DateTime eventDate; // Date of the event
  final Map<String, bool> contacts; // Map of contactId to attendance status (true for present, false for absent)

  Attendance({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.contacts,
  });

  // Convert an Attendance object into a Map for storage or serialization
  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'eventTitle': eventTitle,
      'eventDate': eventDate.toIso8601String(),
      'contacts': contacts.map((key, value) => MapEntry(key, value ? 1 : 0)), // Store boolean as 1 or 0
    };
  }

  // Create an Attendance object from a Map
  static Attendance fromMap(Map<String, dynamic> map) {
    return Attendance(
      eventId: map['eventId'],
      eventTitle: map['eventTitle'],
      eventDate: DateTime.parse(map['eventDate']),
      contacts: (map['contacts'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, value == 1), // Convert 1/0 to true/false
      ),
    );
  }
}