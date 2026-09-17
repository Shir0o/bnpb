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

Contact _weeklyReadingContact(
  String id,
  String firstName,
  String lastName,
  DateTime today,
) {
  return Contact(
    id: id,
    firstName: firstName,
    lastName: lastName,
    updatedAt: today,
    interactions: [
      Interaction(
        participantIds: [id],
        occurredAt: today.subtract(const Duration(days: 21)),
        summary: 'Bible reading',
        medium: 'Coffee',
        notes: 'Psa. 115-116',
      ),
      Interaction(
        participantIds: [id],
        occurredAt: today.subtract(const Duration(days: 14)),
        summary: 'Bible reading',
        medium: 'Coffee',
        notes: 'Psa. 117-118',
      ),
      Interaction(
        participantIds: [id],
        occurredAt: today.subtract(const Duration(days: 7)),
        summary: 'Bible reading',
        medium: 'Coffee',
        notes: 'Psa. 119-120',
      ),
    ],
  );
}

void main() {
  late _FakeDbHelper fakeDbHelper;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

    fakeDbHelper.contacts
        .add(_weeklyReadingContact('contact-1', 'Timothy', 'Alvarez', today));

    await tester.pumpWidget(const MaterialApp(home: RecurringRoutinesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('Bible reading'), findsOneWidget);

    await tester.tap(find.text('Bible reading'));
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Chapters per session'), findsOneWidget);
    expect(find.text('Regular participants'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('combines two routines into one', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    fakeDbHelper.contacts
        .add(_weeklyReadingContact('contact-1', 'Timothy', 'Alvarez', today));
    fakeDbHelper.contacts
        .add(_weeklyReadingContact('contact-2', 'Bob', 'Builder', today));

    await tester.pumpWidget(const MaterialApp(home: RecurringRoutinesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Bible reading'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.merge));
    await tester.pumpAndSettle();

    expect(find.text('Combine routines'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Combine'));
    await tester.pumpAndSettle();

    expect(find.text('Bible reading'), findsOneWidget);
  });

  testWidgets('editing participants adds them to the saved pattern',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    fakeDbHelper.contacts
        .add(_weeklyReadingContact('contact-1', 'Timothy', 'Alvarez', today));
    fakeDbHelper.contacts
        .add(_weeklyReadingContact('contact-2', 'Bob', 'Builder', today));

    await tester.pumpWidget(const MaterialApp(home: RecurringRoutinesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bible reading').first);
    await tester.pumpAndSettle();

    expect(find.text('Bob Builder'), findsOneWidget);

    await tester.tap(find.text('Bob Builder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Timothy Alvarez, Bob Builder'), findsOneWidget);
  });
}
