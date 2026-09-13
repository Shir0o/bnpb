import 'dart:convert';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/screens/recurring_routines_page.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/mock_db_helper.dart';

class _FakeDbHelper extends MockDBHelper {
  final List<Contact> contacts = [];

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return contacts;
  }
}

void main() {
  late _FakeDbHelper fakeDbHelper;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'recurring_log.preferences': jsonEncode({
        'contact-1@@bible reading@@coffee': {'confirmed': true},
      }),
    });
    fakeDbHelper = _FakeDbHelper();
    DBHelper.overrideForTest(fakeDbHelper);
    ContactService().clearCache();
  });

  tearDown(() {
    DBHelper.resetTestOverride();
    ContactService().clearCache();
  });

  testWidgets('lists detected routine and opens the edit dialog',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    fakeDbHelper.contacts.add(
      Contact(
        id: 'contact-1',
        firstName: 'Timothy',
        updatedAt: now,
        interactions: [
          Interaction(
            id: 1,
            participantIds: const ['contact-1'],
            occurredAt: today.subtract(const Duration(days: 21)),
            summary: 'Bible reading',
            medium: 'Coffee',
            notes: 'Psa. 115-116',
          ),
          Interaction(
            id: 2,
            participantIds: const ['contact-1'],
            occurredAt: today.subtract(const Duration(days: 14)),
            summary: 'Bible reading',
            medium: 'Coffee',
            notes: 'Psa. 117-118',
          ),
          Interaction(
            id: 3,
            participantIds: const ['contact-1'],
            occurredAt: today.subtract(const Duration(days: 7)),
            summary: 'Bible reading',
            medium: 'Coffee',
            notes: 'Psa. 119-120',
          ),
        ],
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: RecurringRoutinesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('Bible reading'), findsOneWidget);

    await tester.tap(find.text('Bible reading'));
    await tester.pumpAndSettle();

    expect(find.text('Chapters per session'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
