import 'package:bnpb/models/interaction.dart';

/// An in-memory and staged representation of an exported Simple Time Tracker row,
/// mapped to prospective BNPB contacts and fields for user review.
class CandidateInteraction {
  /// Creates a [CandidateInteraction].
  CandidateInteraction({
    required this.fingerprint,
    required this.occurredAt,
    required this.durationMinutes,
    required this.activityName,
    required this.summary,
    this.medium = 'In Person',
    required this.matchedContactIds,
    required this.rawComment,
    this.selected = true,
  });

  /// SHA-256 fingerprint identifying this time tracker record for deduplication.
  final String fingerprint;

  /// Start timestamp of the tracked activity.
  final DateTime occurredAt;

  /// Duration in minutes, if available.
  final int? durationMinutes;

  /// Name of the activity from the time tracker (e.g., "Contact").
  final String activityName;

  /// Human-readable summary editable by the user.
  String summary;

  /// Medium of the interaction (defaults to "In Person").
  String medium;

  /// Contact IDs matched from the comment or selected by the user.
  List<String> matchedContactIds;

  /// Raw comment string from the time tracker record.
  final String rawComment;

  /// Whether this candidate is selected for import.
  bool selected;

  /// Creates a copy of this [CandidateInteraction].
  CandidateInteraction copyWith({
    String? summary,
    String? medium,
    List<String>? matchedContactIds,
    bool? selected,
  }) {
    return CandidateInteraction(
      fingerprint: fingerprint,
      occurredAt: occurredAt,
      durationMinutes: durationMinutes,
      activityName: activityName,
      summary: summary ?? this.summary,
      medium: medium ?? this.medium,
      matchedContactIds: matchedContactIds ?? List.from(this.matchedContactIds),
      rawComment: rawComment,
      selected: selected ?? this.selected,
    );
  }

  /// Converts this candidate into a committed [Interaction] entity.
  Interaction toInteraction() {
    return Interaction(
      occurredAt: occurredAt,
      summary: summary,
      medium: medium,
      durationMinutes: durationMinutes,
      notes: rawComment.isNotEmpty ? rawComment : null,
      participantIds: List.from(matchedContactIds),
    );
  }

  /// Serializes this candidate to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'fingerprint': fingerprint,
      'occurredAt': occurredAt.toIso8601String(),
      'durationMinutes': durationMinutes,
      'activityName': activityName,
      'summary': summary,
      'medium': medium,
      'matchedContactIds': matchedContactIds,
      'rawComment': rawComment,
      'selected': selected,
    };
  }

  /// Deserializes a [CandidateInteraction] from JSON.
  factory CandidateInteraction.fromJson(Map<String, dynamic> json) {
    return CandidateInteraction(
      fingerprint: json['fingerprint'] as String,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      durationMinutes: json['durationMinutes'] as int?,
      activityName: json['activityName'] as String,
      summary: json['summary'] as String,
      medium: (json['medium'] as String?) ?? 'In Person',
      matchedContactIds: (json['matchedContactIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      rawComment: json['rawComment'] as String? ?? '',
      selected: json['selected'] as bool? ?? true,
    );
  }
}
