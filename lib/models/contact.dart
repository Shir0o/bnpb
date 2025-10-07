import 'dart:convert';

import 'interaction.dart';
import 'prayer_request.dart';

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
  /// Lightweight descriptors that help recognize the contact quickly.
  final List<String> recognitionKeywords;
  /// URIs (web links or storage references) that visually identify the contact.
  final List<String> recognitionPhotoUris;
  /// Gentle reminders tied to this contact (birthdays, follow-ups, etc.).
  final List<String> recognitionReminders;
  /// Recorded interactions for the contact (e.g., meetings, calls).
  final List<Interaction> interactions;
  /// Prayer requests tracked for this contact.
  final List<PrayerRequest> prayerRequests;

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
    List<String>? recognitionKeywords,
    List<String>? recognitionPhotoUris,
    List<String>? recognitionReminders,
    List<Interaction>? interactions,
    List<PrayerRequest>? prayerRequests,
  })  : contactMethods = contactMethods ?? const [],
        tags = tags ?? const [],
        recognitionKeywords = recognitionKeywords ?? const [],
        recognitionPhotoUris = recognitionPhotoUris ?? const [],
        recognitionReminders = recognitionReminders ?? const [],
        interactions = interactions ?? const [],
        prayerRequests = prayerRequests ?? const [];

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
    List<String>? recognitionKeywords,
    List<String>? recognitionPhotoUris,
    List<String>? recognitionReminders,
    List<Interaction>? interactions,
    List<PrayerRequest>? prayerRequests,
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
      recognitionKeywords:
          recognitionKeywords ?? this.recognitionKeywords,
      recognitionPhotoUris:
          recognitionPhotoUris ?? this.recognitionPhotoUris,
      recognitionReminders:
          recognitionReminders ?? this.recognitionReminders,
      interactions: interactions ?? this.interactions,
      prayerRequests: prayerRequests ?? this.prayerRequests,
    );
  }

  // Converts a Contact object into a Map for storage or serialization.
  // Notice: We keep `interactions` as a List of Maps here.
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
      'recognitionKeywords': recognitionKeywords,
      'recognitionPhotoUris': recognitionPhotoUris,
      'recognitionReminders': recognitionReminders,
      'interactions': interactions.map((entry) => entry.toMap()).toList(),
      'prayerRequests':
          prayerRequests.map((entry) => entry.toMap()).toList(),
    };
  }

  // Creates a Contact object from a Map that already has `interactions` as a List of Maps.
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
      recognitionKeywords: _parseStringList(map['recognitionKeywords']),
      recognitionPhotoUris: _parseStringList(map['recognitionPhotoUris']),
      recognitionReminders: _parseStringList(map['recognitionReminders']),
      interactions: (map['interactions'] as List<dynamic>?)
              ?.map((entry) =>
                  Interaction.fromMap(Map<String, dynamic>.from(entry)))
              .toList() ??
          const [],
      prayerRequests: (map['prayerRequests'] as List<dynamic>?)
              ?.map((entry) =>
                  PrayerRequest.fromMap(Map<String, dynamic>.from(entry)))
              .toList() ??
          const [],
    );
  }

  // Combines first, middle, and last names into a single full name
  String get fullName {
    final parts = [firstName, middleName, if (lastName != null) lastName!]
        .where((name) => name.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.join(' ') : (nickname ?? '');
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((entry) => entry.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((entry) => entry.toString()).toList();
        }
      } catch (_) {
        return value
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }
}
