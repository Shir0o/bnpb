import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/contact_stage.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/stage_move.dart';

import 'package:bnpb/services/contact_stage_service.dart';
import '../repositories/mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  List<Contact> contacts = [];
  final List<StageMove> stageMoves = [];

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return contacts;
  }

  @override
  Future<Contact?> getContactById(String id) async {
    for (final contact in contacts) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  @override
  Future<void> setContactStage({
    required String contactId,
    required String toStage,
    String? fromStage,
    DateTime? movedAt,
  }) async {
    final index = contacts.indexWhere((c) => c.id == contactId);
    if (index >= 0) {
      contacts[index] = contacts[index].copyWith(stage: toStage);
    }
    stageMoves.add(
      StageMove(
        contactId: contactId,
        fromStage: fromStage,
        toStage: toStage,
        movedAt: movedAt ?? DateTime.now(),
      ),
    );
  }
}

Contact _contact(
  String id,
  String name,
  int interactionCount, {
  String? stage,
}) {
  final parts = name.split(' ');
  final now = DateTime(2026, 8, 17);
  return Contact(
    id: id,
    firstName: parts.first,
    lastName: parts.length > 1 ? parts.last : null,
    stage: stage,
    updatedAt: now,
    interactions: [
      for (var i = 0; i < interactionCount; i++)
        Interaction(
          occurredAt: DateTime(2026, 8, 2 + i),
          summary: 'Chat',
          medium: 'Call',
        ),
    ],
  );
}

void main() {
  late _TestDBHelper dbHelper;
  late ContactStageService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dbHelper = _TestDBHelper();
    service = ContactStageService();
    DBHelper.overrideForTest(dbHelper);
  });

  tearDown(() {
    DBHelper.resetTestOverride();
  });

  group('defaultStageFor', () {
    test('maps interaction counts to initial stages', () {
      expect(defaultStageFor(0), ContactStage.firstContact);
      expect(defaultStageFor(1), ContactStage.firstContact);
      expect(defaultStageFor(2), ContactStage.secondContact);
      expect(defaultStageFor(3), ContactStage.secondContact);
      expect(defaultStageFor(4), ContactStage.regularContact);
      expect(defaultStageFor(99), ContactStage.regularContact);
    });
  });

  group('buildSuggestions', () {
    test('proposes a one-step advance when activity outpaces the stage',
        () async {
      dbHelper.contacts
          .add(_contact('c1', 'Gus Hall', 5, stage: 'First contact'));

      final suggestions = await service.buildSuggestions(dbHelper.contacts);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.from, 'First contact');
      expect(suggestions.single.to, 'Second contact');
      expect(suggestions.single.path, 'First contact → Second contact');
      expect(suggestions.single.why, contains('5 interactions'));
    });

    test('no suggestion when the stage already matches the activity', () async {
      dbHelper.contacts
          .add(_contact('c1', 'Ann Lee', 2, stage: 'Second contact'));
      dbHelper.contacts
          .add(_contact('c2', 'Cal Poe', 6, stage: 'Regular contact'));

      final suggestions = await service.buildSuggestions(dbHelper.contacts);

      expect(suggestions, isEmpty);
    });

    test('dismissed suggestions are not re-proposed', () async {
      dbHelper.contacts
          .add(_contact('c1', 'Gus Hall', 5, stage: 'First contact'));
      await service.dismissSuggestion('c1', 'Second contact');

      final suggestions = await service.buildSuggestions(dbHelper.contacts);

      expect(suggestions, isEmpty);
    });
  });

  group('confirmSuggestion', () {
    test('persists the stage, records a move, and dismisses the suggestion',
        () async {
      // 3 interactions only justify reaching Second contact, so after
      // confirming there is nothing further to suggest.
      dbHelper.contacts
          .add(_contact('c1', 'Gus Hall', 3, stage: 'First contact'));

      await service.confirmSuggestion('c1', 'Second contact');

      expect(dbHelper.contacts.single.stage, 'Second contact');
      expect(dbHelper.stageMoves, hasLength(1));
      expect(dbHelper.stageMoves.single.fromStage, 'First contact');
      expect(dbHelper.stageMoves.single.toStage, 'Second contact');

      final suggestions = await service.buildSuggestions(dbHelper.contacts);
      expect(suggestions, isEmpty);
    });
  });

  group('setStage', () {
    test('records a move and updates the contact stage', () async {
      dbHelper.contacts.add(_contact('c1', 'Ann Lee', 2));

      await service.setStage(
          dbHelper.contacts.single, ContactStage.groupMeeting);

      expect(dbHelper.contacts.single.stage, 'Group meeting');
      expect(dbHelper.stageMoves.single.fromStage, 'Second contact');
      expect(dbHelper.stageMoves.single.toStage, 'Group meeting');
    });

    test('no-op when the target equals the current stage', () async {
      dbHelper.contacts
          .add(_contact('c1', 'Ann Lee', 2, stage: 'Regular contact'));

      await service.setStage(
          dbHelper.contacts.single, ContactStage.regularContact);

      expect(dbHelper.stageMoves, isEmpty);
    });
  });
}
