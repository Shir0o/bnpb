import 'package:uuid/uuid.dart';

/// A confirmed stage change. These drive the review's "who actually moved"
/// story — nothing counts toward movement until a stage is set or confirmed.
class StageMove {
  StageMove({
    this.id,
    String? syncId,
    required this.contactId,
    this.fromStage,
    required this.toStage,
    required this.movedAt,
    DateTime? updatedAt,
    this.deletedAt,
  })  : syncId = syncId ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  final int? id;
  final String syncId;
  final String contactId;

  /// May be null for the first recorded move.
  final String? fromStage;
  final String toStage;
  final DateTime movedAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = <String, dynamic>{
      'syncId': syncId,
      'contactId': contactId,
      'fromStage': fromStage,
      'toStage': toStage,
      'movedAt': movedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  static StageMove fromMap(Map<String, dynamic> map) {
    return StageMove(
      id: map['id'] as int?,
      syncId: map['syncId'] as String?,
      contactId: map['contactId'] as String,
      fromStage: map['fromStage'] as String?,
      toStage: map['toStage'] as String,
      movedAt: DateTime.parse(map['movedAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }
}
