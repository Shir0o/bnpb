import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/models/stage_move.dart';
import 'package:bnpb/screens/contact_details_page.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import '../repositories/mock_db_helper.dart';

class MockContactService extends Mock implements ContactService {}

/// In-memory stand-in for the SQLCipher-backed DBHelper. Stores the whole
/// contact row the same shape the real `contacts` table does, so a save that
/// drops a column is observable here.
class InMemoryDBHelper extends MockDBHelper {
  InMemoryDBHelper(this.contacts);

  final Map<String, Contact> contacts;
  final List<StageMove> moves = [];

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return contacts.values.toList();
  }

  @override
  Future<Contact?> getContactById(String id) async => contacts[id];

  @override
  Future<List<Relationship>> getRelationshipsForContact(
    String contactId,
  ) async =>
      [];

  @override
  Future<List<String>> getDistinctLocations() async => [];

  @override
  Future<void> setContactStage({
    required String contactId,
    required String toStage,
    String? fromStage,
    DateTime? movedAt,
  }) async {
    final contact = contacts[contactId];
    if (contact != null) {
      contacts[contactId] = contact.copyWith(stage: toStage);
    }
    moves.add(
      StageMove(
        contactId: contactId,
        fromStage: fromStage,
        toStage: toStage,
        movedAt: movedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateContact(Contact contact) async {
    contacts[contact.id] = contact;
  }
}

Contact _annLee() => Contact(
      id: 'c1',
      firstName: 'Ann',
      lastName: 'Lee',
      // Zero interactions, but the user explicitly set a deeper stage.
      stage: 'Group meeting',
      interactions: const [],
    );

Future<void> _pumpPage(
  WidgetTester tester,
  Contact contact,
  InMemoryDBHelper db,
) async {
  final service = MockContactService();
  when(() => service.hasCachedInteractions(any())).thenReturn(false);
  when(
    () => service.getInteractions(any(),
        forceRefresh: any(named: 'forceRefresh')),
  ).thenAnswer((_) async => []);

  await tester.pumpWidget(
    MaterialApp(
      home: ContactDetailsPage(
        contact: contact,
        onDelete: () async {},
        contactService: service,
        dbHelper: db,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US', null);
  });

  testWidgets(
    'contact detail renders the STORED stage, not the interaction-derived default',
    (tester) async {
      final original = _annLee();
      final db = InMemoryDBHelper({'c1': original});
      DBHelper.overrideForTest(db);
      addTearDown(DBHelper.resetTestOverride);

      await _pumpPage(tester, original, db);

      expect(
        find.text('Group meeting'),
        findsOneWidget,
        reason: 'the STAGE card must show the persisted stage on reopen',
      );
    },
  );

  testWidgets(
    'saving an edited contact keeps the stored stage column',
    (tester) async {
      final original = _annLee();
      final db = InMemoryDBHelper({'c1': original});
      DBHelper.overrideForTest(db);
      addTearDown(DBHelper.resetTestOverride);

      await _pumpPage(tester, original, db);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      final saved = db.contacts['c1'];
      expect(
        saved?.stage,
        'Group meeting',
        reason: 'an unrelated edit must not wipe the stage column',
      );
    },
  );
}
