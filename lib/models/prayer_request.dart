import 'package:flutter/foundation.dart';

/// Represents the lifecycle state for a [PrayerRequest].
enum PrayerRequestStatus {
  /// Request is still active and waiting on an answer.
  pending,

  /// Request has been answered and can surface in praise reports.
  answered,

  /// Request is archived or no longer actively tracked.
  archived,
}

/// Extension helpers for formatting and parsing [PrayerRequestStatus] values.
extension PrayerRequestStatusX on PrayerRequestStatus {
  /// Human-readable label for displaying the status in the UI.
  String get label {
    switch (this) {
      case PrayerRequestStatus.pending:
        return 'Pending';
      case PrayerRequestStatus.answered:
        return 'Answered';
      case PrayerRequestStatus.archived:
        return 'Archived';
    }
  }

  /// Converts a database string into the corresponding status enum.
  static PrayerRequestStatus fromStorage(String? value) {
    return PrayerRequestStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => PrayerRequestStatus.pending,
    );
  }
}

/// Captures a prayer request linked to a contact and optionally an interaction.
@immutable
class PrayerRequest {
  const PrayerRequest({
    this.id,
    required this.contactId,
    this.interactionId,
    required this.description,
    required this.status,
    required this.requestedAt,
    this.answeredAt,
    this.category,
    this.reflectionNotes,
  });

  /// Row identifier when persisted.
  final int? id;

  /// Contact that owns the prayer request.
  final String contactId;

  /// Optional interaction that spawned the request.
  final int? interactionId;

  /// Summary of the prayer need.
  final String description;

  /// Lifecycle state for the request.
  final PrayerRequestStatus status;

  /// When the request was first recorded.
  final DateTime requestedAt;

  /// When the request was answered, if available.
  final DateTime? answeredAt;

  /// Optional category to group similar requests.
  final String? category;

  /// Reflection or gratitude notes once the prayer is answered.
  final String? reflectionNotes;

  /// Returns a copy with selective overrides.
  PrayerRequest copyWith({
    int? id,
    String? contactId,
    int? interactionId,
    String? description,
    PrayerRequestStatus? status,
    DateTime? requestedAt,
    DateTime? answeredAt,
    String? category,
    String? reflectionNotes,
  }) {
    return PrayerRequest(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      interactionId: interactionId ?? this.interactionId,
      description: description ?? this.description,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      category: category ?? this.category,
      reflectionNotes: reflectionNotes ?? this.reflectionNotes,
    );
  }

  /// Serialises the request for persistence.
  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = <String, dynamic>{
      'contactId': contactId,
      'interactionId': interactionId,
      'description': description,
      'status': status.name,
      'requestedAt': requestedAt.toIso8601String(),
      'answeredAt': answeredAt?.toIso8601String(),
      'category': category,
      'reflectionNotes': reflectionNotes,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  /// Restores a [PrayerRequest] from persistence.
  factory PrayerRequest.fromMap(Map<String, dynamic> map) {
    return PrayerRequest(
      id: map['id'] as int?,
      contactId: map['contactId'] as String,
      interactionId: map['interactionId'] as int?,
      description: map['description'] as String,
      status: PrayerRequestStatusX.fromStorage(map['status'] as String?),
      requestedAt: DateTime.parse(map['requestedAt'] as String),
      answeredAt: map['answeredAt'] != null
          ? DateTime.tryParse(map['answeredAt'] as String)
          : null,
      category: map['category'] as String?,
      reflectionNotes: map['reflectionNotes'] as String?,
    );
  }
}
