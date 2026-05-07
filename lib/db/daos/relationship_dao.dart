import '../../models/relationship.dart';
import '../base_dao.dart';

class RelationshipDao extends BaseDao {
  RelationshipDao(super.dbHelper);

  Future<Relationship> upsertRelationship(Relationship relationship) async {
    final db = await database;

    if (relationship.id == null) {
      final id = await db.insert(
        'relationships',
        relationship.toMap(includeId: false),
      );
      return relationship.copyWith(id: id);
    } else {
      await db.update(
        'relationships',
        relationship.toMap(includeId: false),
        where: 'id = ?',
        whereArgs: [relationship.id],
      );
      return relationship;
    }
  }

  /// Inserts many relationships in a single transaction. Used by import flows
  /// to avoid one transaction per row.
  Future<void> insertRelationshipsBulk(
    Iterable<Relationship> relationships,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final relationship in relationships) {
        batch.insert('relationships', relationship.toMap(includeId: false));
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteRelationship(int id) async {
    final db = await database;
    await db.delete('relationships', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Relationship>> getRelationshipsForContact(
    String contactId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'relationships',
      where: 'sourceContactId = ? OR targetContactId = ?',
      whereArgs: [contactId, contactId],
    );

    return rows
        .map((row) => Relationship.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<Relationship>> getAllRelationships() async {
    final db = await database;
    final rows = await db.query('relationships');
    return rows
        .map((row) => Relationship.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Map<String, List<Relationship>>> getRelationshipsForContacts(
    List<String> contactIds,
    Set<String> retrievedContactIdsSet, {
    bool isFetchAllActive = false,
  }) async {
    final db = await database;
    final List<Map<String, Object?>> relRows;

    if (isFetchAllActive) {
      relRows = await db.rawQuery('''
         SELECT r.* FROM relationships r
         JOIN contacts s ON r.sourceContactId = s.id
         JOIN contacts t ON r.targetContactId = t.id
         WHERE s.deletedAt IS NULL OR t.deletedAt IS NULL
       ''');
    } else {
      relRows = [];
      const int batchSize = 450;
      for (var i = 0; i < contactIds.length; i += batchSize) {
        final end = (i + batchSize < contactIds.length)
            ? i + batchSize
            : contactIds.length;
        final chunk = contactIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');

        final rows = await db.query(
          'relationships',
          where:
              'sourceContactId IN ($placeholders) OR targetContactId IN ($placeholders)',
          whereArgs: [...chunk, ...chunk],
        );
        relRows.addAll(rows);
      }
    }

    final relationshipsByContact = <String, List<Relationship>>{};
    for (final row in relRows) {
      final src = row['sourceContactId'] as String;
      final tgt = row['targetContactId'] as String;
      if (retrievedContactIdsSet.contains(src)) {
        relationshipsByContact
            .putIfAbsent(src, () => [])
            .add(Relationship.fromMap(Map<String, dynamic>.from(row)));
      }
      if (retrievedContactIdsSet.contains(tgt)) {
        relationshipsByContact
            .putIfAbsent(tgt, () => [])
            .add(Relationship.fromMap(Map<String, dynamic>.from(row)));
      }
    }

    return relationshipsByContact;
  }
}
