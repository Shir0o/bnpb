/// Describes a directed connection between two contacts.
class Relationship {
  const Relationship({
    this.id,
    required this.sourceContactId,
    required this.targetContactId,
    required this.type,
    this.notes,
  });

  /// Primary key of the persisted relationship row.
  final int? id;

  /// Contact identifier that initiates the relationship.
  final String sourceContactId;

  /// Contact identifier on the receiving side of the relationship.
  final String targetContactId;

  /// Free-form category describing the relationship (e.g. "Friend", "Mentor").
  final String type;

  /// Optional notes that provide more context about the connection.
  final String? notes;

  Relationship copyWith({
    int? id,
    String? sourceContactId,
    String? targetContactId,
    String? type,
    String? notes,
  }) {
    return Relationship(
      id: id ?? this.id,
      sourceContactId: sourceContactId ?? this.sourceContactId,
      targetContactId: targetContactId ?? this.targetContactId,
      type: type ?? this.type,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = <String, dynamic>{
      'sourceContactId': sourceContactId,
      'targetContactId': targetContactId,
      'type': type,
      'notes': notes,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory Relationship.fromMap(Map<String, dynamic> map) {
    return Relationship(
      id: map['id'] as int?,
      sourceContactId: map['sourceContactId'] as String,
      targetContactId: map['targetContactId'] as String,
      type: map['type'] as String,
      notes: map['notes'] as String?,
    );
  }
}
