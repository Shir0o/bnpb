import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';

void main() {
  test('upsertContactRowForTest rewrites interactions atomically', () async {
    final helper = DBHelper();
    final fakeTxn = _FakeTransaction();
    final contact = Contact(
      id: 'contact-123',
      firstName: 'Ada',
      interactions: [
        Interaction(
          occurredAt: DateTime.parse('2024-01-15T12:00:00.000Z'),
          summary: 'Coffee chat',
          medium: 'in_person',
          location: 'Downtown',
          attachments: const [
            AttachmentReference(
              uri: 'file://note',
              source: AttachmentSource.local,
              label: 'Conversation notes',
            ),
          ],
          markForPrayer: true,
          followUpAt: DateTime.parse('2024-01-16T12:30:00.000Z'),
          durationMinutes: 45,
          category: 'catchUp',
        ),
      ],
    );

    await helper.upsertContactRowForTest(
      fakeTxn,
      contact,
      isUpdate: false,
    );

    // Expect soft delete (update) instead of hard delete
    final interactionUpdates = fakeTxn.updateCalls
        .where((call) =>
            call.table == 'interactions' &&
            call.values.containsKey('deletedAt'))
        .toList();
    expect(interactionUpdates, hasLength(1));
    expect(interactionUpdates.first.where, 'id = ?');
    expect(interactionUpdates.first.whereArgs, [999]);

    final interactionInserts = fakeTxn.insertCalls
        .where((call) => call.table == 'interactions')
        .toList();
    expect(interactionInserts, hasLength(1));

    final inserted = interactionInserts.first.values;
    expect(inserted.containsKey('id'), isFalse);
    expect(
      inserted['occurredAt'],
      contact.interactions.first.occurredAt.toIso8601String(),
    );
    expect(inserted['markForPrayer'], 1);

    final attachmentsJson = inserted['attachments'] as String;
    final attachments = jsonDecode(attachmentsJson) as List<dynamic>;
    expect(attachments, hasLength(1));
    final encoded = attachments.first as Map<String, dynamic>;
    expect(encoded['uri'], 'file://note');
    expect(encoded['source'], AttachmentSource.local.name);
    expect(encoded['label'], 'Conversation notes');

    final updateIndex = fakeTxn.callOrder.indexOf('update:interactions');
    final insertIndex = fakeTxn.callOrder.indexOf('insert:interactions');
    expect(updateIndex, isNonNegative);
    expect(insertIndex, isNonNegative);
    // Insert happens before soft delete of orphans (which happens at end)
    expect(insertIndex, lessThan(updateIndex));
  });

  test('Interaction.fromMap accepts markForPrayer in multiple formats', () {
    Map<String, dynamic> buildInteraction(dynamic markForPrayer) {
      return {
        'contactId': 'contact-123',
        'occurredAt': '2024-01-15T12:00:00.000Z',
        'summary': 'Coffee chat',
        'medium': 'in_person',
        'attachments': const [],
        'markForPrayer': markForPrayer,
      };
    }

    final boolBacked = Interaction.fromMap(buildInteraction(true));
    expect(boolBacked.markForPrayer, isTrue);

    final intBacked = Interaction.fromMap(buildInteraction(1));
    expect(intBacked.markForPrayer, isTrue);

    final stringTrue = Interaction.fromMap(buildInteraction('true'));
    expect(stringTrue.markForPrayer, isTrue);

    final stringOne = Interaction.fromMap(buildInteraction('1'));
    expect(stringOne.markForPrayer, isTrue);

    final falsey = Interaction.fromMap(buildInteraction(0));
    expect(falsey.markForPrayer, isFalse);
  });
}

class _InsertCall {
  _InsertCall(this.table, this.values, this.conflictAlgorithm);

  final String table;
  final Map<String, Object?> values;
  final ConflictAlgorithm? conflictAlgorithm;
}

class _DeleteCall {
  _DeleteCall(this.table, this.where, this.whereArgs);

  final String table;
  final String? where;
  final List<Object?>? whereArgs;
}

class _UpdateCall {
  _UpdateCall(this.table, this.values, this.where, this.whereArgs);

  final String table;
  final Map<String, Object?> values;
  final String? where;
  final List<Object?>? whereArgs;
}

class _FakeTransaction implements DatabaseExecutor {
  final List<_InsertCall> insertCalls = [];
  final List<_DeleteCall> deleteCalls = [];
  final List<_UpdateCall> updateCalls = [];
  final List<String> callOrder = [];

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    callOrder.add('delete:$table');
    deleteCalls.add(_DeleteCall(table, where, whereArgs));
    return 1;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    callOrder.add('insert:$table');
    insertCalls.add(
      _InsertCall(table, Map<String, Object?>.from(values), conflictAlgorithm),
    );
    return 1;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    callOrder.add('update:$table');
    updateCalls.add(
      _UpdateCall(table, Map<String, Object?>.from(values), where, whereArgs),
    );
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return [];
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql.contains('SELECT id FROM interactions WHERE id NOT IN')) {
      // Mock finding an orphan
      return [
        {'id': 999}
      ];
    }
    return [];
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Batch batch() {
    throw UnimplementedError();
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) {
    throw UnimplementedError();
  }

  @override
  Database get database => throw UnimplementedError();
}
