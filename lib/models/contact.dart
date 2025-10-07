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

/// A single way to reach a contact, such as an email address or phone number.
class ContactMethod {
  final String type;
  final String value;
  final String? label;

  const ContactMethod({
    required this.type,
    required this.value,
    this.label,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'value': value,
      'label': label,
    };
  }

  factory ContactMethod.fromMap(Map<String, dynamic> map) {
    return ContactMethod(
      type: map['type'] as String,
      value: map['value'] as String,
      label: map['label'] as String?,
    );
  }
}

class Contact {
  final String id; // Unique identifier for the contact
  final String firstName; // First name of the contact
  final String middleName; // Middle name of the contact (optional)
  final String? lastName; // Last name of the contact (optional)
  final String? nickname; // Nickname of the contact (optional)
  final String? location; // Location of the contact (optional)
  final String? metThroughId; // Identifier for the person who introduced the contact
  final String? firstMeetingNotes; // Notes from the first meeting
  final List<ContactMethod> contactMethods; // Reachable methods (phone/email)
  final List<String> tags; // Relationship tags
  final List<HistoryEntry> history; // List of history entries for the contact

  Contact({
    required this.id,
    required this.firstName,
    this.middleName = '',
    this.lastName,
    this.nickname,
    this.location,
    this.metThroughId,
    this.firstMeetingNotes,
    List<ContactMethod>? contactMethods,
    List<String>? tags,
    List<HistoryEntry>? history,
  })  : contactMethods = contactMethods ?? const [],
        tags = tags ?? const [],
        history = history ?? [];

  Contact copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    String? location,
    String? metThroughId,
    bool clearMetThroughId = false,
    String? firstMeetingNotes,
    List<ContactMethod>? contactMethods,
    List<String>? tags,
    List<HistoryEntry>? history,
  }) {
    return Contact(
      id: id,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      nickname: nickname ?? this.nickname,
      location: location ?? this.location,
      metThroughId: clearMetThroughId
          ? null
          : (metThroughId ?? this.metThroughId),
      firstMeetingNotes: firstMeetingNotes ?? this.firstMeetingNotes,
      contactMethods: contactMethods ?? this.contactMethods,
      tags: tags ?? this.tags,
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
      'lastName': lastName,
      'nickname': nickname,
      'location': location,
      'metThroughId': metThroughId,
      'firstMeetingNotes': firstMeetingNotes,
      'contactMethods': contactMethods.map((entry) => entry.toMap()).toList(),
      'tags': tags,
      'history': history.map((entry) => entry.toMap()).toList(),
    };
  }

  // Creates a Contact object from a Map that already has `history` as a List of Maps.
  static Contact fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'] as String,
      firstName: map['firstName'] as String,
      middleName: (map['middleName'] ?? '') as String,
      lastName: map['lastName'] as String?,
      nickname: map['nickname'] as String?,
      location: map['location'] as String?,
      metThroughId: map['metThroughId'] as String?,
      firstMeetingNotes: map['firstMeetingNotes'] as String?,
      contactMethods: (map['contactMethods'] as List<dynamic>?)
              ?.map((entry) =>
                  ContactMethod.fromMap(Map<String, dynamic>.from(entry)))
              .toList() ??
          const [],
      tags: (map['tags'] as List<dynamic>?)
              ?.map((tag) => tag as String)
              .toList() ??
          const [],
      history: (map['history'] as List<dynamic>?)
              ?.map((entry) =>
                  HistoryEntry.fromMap(Map<String, dynamic>.from(entry)))
              .toList() ??
          [],
    );
  }

  // Combines first, middle, and last names into a single full name
  String get fullName {
    final parts = [firstName, middleName, if (lastName != null) lastName!]
        .where((name) => name.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.join(' ') : (nickname ?? '');
  }
}