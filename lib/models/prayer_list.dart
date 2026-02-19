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
    DateTime? updatedAt,
    this.deletedAt,
  })  : contactIds = contactIds ?? const [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String? description;
  final String? color; // Hex string, e.g. "0xFF4287F5"
  final int displayIndex;
  final List<String> contactIds;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  PrayerList copyWith({
    String? name,
    String? description,
    String? color,
    int? displayIndex,
    List<String>? contactIds,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return PrayerList(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      displayIndex: displayIndex ?? this.displayIndex,
      contactIds: contactIds ?? this.contactIds,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'displayIndex': displayIndex,
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }

  static PrayerList fromMap(Map<String, dynamic> map,
      {List<String>? contactIds}) {
    // If contactIds arg is null, try to read from map
    var ids = contactIds;
    if (ids == null && map['contactIds'] != null) {
      if (map['contactIds'] is List) {
        ids = (map['contactIds'] as List).map((e) => e.toString()).toList();
      }
    }

    return PrayerList(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as String?,
      displayIndex: map['displayIndex'] as int? ?? 0,
      contactIds: ids,
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      deletedAt: map['deletedAt'] != null
          ? DateTime.parse(map['deletedAt'] as String)
          : null,
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
