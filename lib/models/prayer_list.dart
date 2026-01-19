import 'package:uuid/uuid.dart';

/// Represents a user-created list of contacts for focused prayer.
class PrayerList {
  PrayerList({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.displayIndex = 0,
    List<String>? contactIds,
  }) : contactIds = contactIds ?? const [];

  final String id;
  final String name;
  final String? description;
  final String? color; // Hex string, e.g. "0xFF4287F5"
  final int displayIndex;
  final List<String> contactIds;

  PrayerList copyWith({
    String? name,
    String? description,
    String? color,
    int? displayIndex,
    List<String>? contactIds,
  }) {
    return PrayerList(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      displayIndex: displayIndex ?? this.displayIndex,
      contactIds: contactIds ?? this.contactIds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'displayIndex': displayIndex,
    };
  }

  static PrayerList fromMap(Map<String, dynamic> map, {List<String>? contactIds}) {
    return PrayerList(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as String?,
      displayIndex: map['displayIndex'] as int? ?? 0,
      contactIds: contactIds,
    );
  }

  static PrayerList create({
    required String name,
    String? description,
    String? color,
  }) {
    return PrayerList(
      id: const Uuid().v4(),
      name: name,
      description: description,
      color: color,
    );
  }
}
