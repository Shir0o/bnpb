import 'dart:convert';

/// Describes the source for an [AttachmentReference].
enum AttachmentSource {
  /// Attachment stored locally on the device file system.
  local,

  /// Attachment hosted remotely (e.g., cloud storage or shared link).
  cloud,
}

/// A lightweight pointer to a file or external resource associated with an
/// [Interaction].
class AttachmentReference {
  const AttachmentReference({
    required this.uri,
    required this.source,
    this.label,
  });

  final String uri;
  final AttachmentSource source;
  final String? label;

  AttachmentReference copyWith({
    String? uri,
    AttachmentSource? source,
    String? label,
  }) {
    return AttachmentReference(
      uri: uri ?? this.uri,
      source: source ?? this.source,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uri': uri,
      'source': source.name,
      'label': label,
    };
  }

  static AttachmentReference fromMap(Map<String, dynamic> map) {
    final sourceValue = map['source'] as String?;
    return AttachmentReference(
      uri: map['uri'] as String,
      source: AttachmentSource.values.firstWhere(
        (value) => value.name == sourceValue,
        orElse: () => AttachmentSource.local,
      ),
      label: map['label'] as String?,
    );
  }
}

/// Represents an interaction with a contact, including where, when and how it
/// took place.
class Interaction {
  const Interaction({
    this.id,
    required this.occurredAt,
    required this.summary,
    required this.medium,
    this.location,
    this.attachments = const [],
    this.markForPrayer = false,
    this.followUpAt,
    this.durationMinutes,
    this.category,
    this.participantIds = const [],
  });

  final int? id;
  final List<String> participantIds;
  final DateTime occurredAt;
  final String summary;
  final String medium;
  final String? location;
  final List<AttachmentReference> attachments;
  final bool markForPrayer;
  final DateTime? followUpAt;
  final int? durationMinutes;
  final String? category;

  Interaction copyWith({
    int? id,
    DateTime? occurredAt,
    String? summary,
    String? medium,
    String? location,
    List<AttachmentReference>? attachments,
    bool? markForPrayer,
    DateTime? followUpAt,
    int? durationMinutes,
    String? category,
    List<String>? participantIds,
  }) {
    return Interaction(
      id: id ?? this.id,
      occurredAt: occurredAt ?? this.occurredAt,
      summary: summary ?? this.summary,
      medium: medium ?? this.medium,
      location: location ?? this.location,
      attachments: attachments ?? this.attachments,
      markForPrayer: markForPrayer ?? this.markForPrayer,
      followUpAt: followUpAt ?? this.followUpAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      category: category ?? this.category,
      participantIds: participantIds ?? this.participantIds,
    );
  }

  Map<String, dynamic> toMap({
    bool includeId = true,
    bool encodeAttachments = true,
  }) {
    final map = toJson(includeId: includeId);
    if (encodeAttachments) {
      map['attachments'] = jsonEncode(map['attachments']);
    }
    map['markForPrayer'] = markForPrayer ? 1 : 0;
    return map;
  }

  /// Serializes the interaction into a JSON-friendly map.
  ///
  /// Attachments are emitted as a list of maps so export flows can embed them
  /// without additional decoding.
  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'occurredAt': occurredAt.toIso8601String(),
      'summary': summary,
      'medium': medium,
      'location': location,
      'attachments':
          attachments.map((attachment) => attachment.toMap()).toList(),
      'markForPrayer': markForPrayer,
      'followUpAt': followUpAt?.toIso8601String(),
      'durationMinutes': durationMinutes,
      'category': category,
      'participantIds': participantIds,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  static Interaction fromMap(Map<String, dynamic> map) {
    final rawAttachments = map['attachments'];
    List<AttachmentReference> parsedAttachments;
    if (rawAttachments is String && rawAttachments.isNotEmpty) {
      final decoded = jsonDecode(rawAttachments) as List<dynamic>;
      parsedAttachments = decoded
          .map((entry) =>
              AttachmentReference.fromMap(Map<String, dynamic>.from(entry)))
          .toList();
    } else if (rawAttachments is List) {
      parsedAttachments = rawAttachments
          .map((entry) =>
              AttachmentReference.fromMap(Map<String, dynamic>.from(entry)))
          .toList();
    } else {
      parsedAttachments = const [];
    }

    return Interaction(
      id: map['id'] as int?,
      occurredAt: DateTime.parse(map['occurredAt'] as String),
      summary: map['summary'] as String,
      medium: map['medium'] as String,
      location: map['location'] as String?,
      attachments: parsedAttachments,
      markForPrayer: _parseMarkForPrayer(map['markForPrayer']),
      followUpAt: map['followUpAt'] != null
          ? DateTime.tryParse(map['followUpAt'] as String)
          : null,
      durationMinutes: _parseOptionalInt(map['durationMinutes']),
      category: _parseOptionalCategory(map['category']),
      participantIds: _parseParticipantIds(map['participantIds']),
    );
  }

  static List<String> _parseParticipantIds(dynamic value) {
    // Optimization: Return directly if already typed correctly to avoid O(N) copy.
    if (value is List<String>) {
      return value;
    }
    if (value is List) {
      return value.map((entry) => entry.toString()).toList();
    }
    return const [];
  }

  static int? _parseOptionalInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool _parseMarkForPrayer(dynamic value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value == 1;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
      final parsedInt = int.tryParse(normalized);
      if (parsedInt != null) {
        return parsedInt == 1;
      }
    }
    return false;
  }

  static String? _parseOptionalCategory(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
