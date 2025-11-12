import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'interaction.dart';
import 'prayer_request.dart';

class Contact {
  final String id; // Unique identifier for the contact
  final String firstName; // First name of the contact
  final String middleName; // Middle name of the contact (optional)
  final String? lastName; // Last name of the contact (optional)
  final String? nickname; // Nickname of the contact (optional)
  final String? location; // Location of the contact (optional)
  /// Dietary restrictions or preferences shared by the contact.
  final String? dietaryPreference;
  final String? firstMeetingNotes; // Notes from the first meeting
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
    this.dietaryPreference,
    this.firstMeetingNotes,
    List<String>? tags,
    List<String>? recognitionKeywords,
    List<String>? recognitionPhotoUris,
    List<String>? recognitionReminders,
    List<Interaction>? interactions,
    List<PrayerRequest>? prayerRequests,
  })  : tags = tags ?? const [],
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
    String? dietaryPreference,
    String? firstMeetingNotes,
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
      dietaryPreference: dietaryPreference ?? this.dietaryPreference,
      firstMeetingNotes: firstMeetingNotes ?? this.firstMeetingNotes,
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
      'dietaryPreference': dietaryPreference,
      'firstMeetingNotes': firstMeetingNotes,
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
    final contactId = (map['id'] as String?)?.trim();
    return Contact(
      id:
          contactId != null && contactId.isNotEmpty ? contactId : const Uuid().v4(),
      firstName: map['firstName'] as String,
      middleName: (map['middleName'] ?? '') as String,
      lastName: map['lastName'] as String?,
      nickname: map['nickname'] as String?,
      location: map['location'] as String?,
      dietaryPreference: map['dietaryPreference'] as String?,
      firstMeetingNotes: map['firstMeetingNotes'] as String?,
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
