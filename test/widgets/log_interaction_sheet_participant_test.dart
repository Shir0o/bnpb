import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/widgets/contact_selection_sheet.dart';
import 'package:bnpb/widgets/log_interaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDBHelper extends Mock implements DBHelper {}

void main() {
  late MockDBHelper mockDBHelper;

  setUp(() {
    mockDBHelper = MockDBHelper();
    DBHelper.overrideForTest(mockDBHelper);
  });

  tearDown(() {
    DBHelper.resetTestOverride();
  });

  testWidgets(
      'LogInteractionSheet displays contact name when a new participant is selected',
      (WidgetTester tester) async {
    final primaryContact =
        Contact(id: 'c1', firstName: 'Primary', lastName: 'User');
    final newlyCreatedContact = Contact(
      id: '2026-09-06T21:46:34.682592',
      firstName: 'New',
      lastName: 'Person',
    );

    when(() => mockDBHelper.getContacts()).thenAnswer(
      (_) async => [primaryContact, newlyCreatedContact],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogInteractionSheet(
            contact: primaryContact,
            existingInteractions: const [],
            availableContacts: [primaryContact],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Primary User'), findsOneWidget);

    await tester.tap(find.text('Add participant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ContactSelectionSheet), findsOneWidget);

    Navigator.of(tester.element(find.byType(ContactSelectionSheet)))
        .pop([newlyCreatedContact.id]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // This should assert that the name is shown and raw ISO id is NOT shown
    expect(find.text('New Person'), findsOneWidget);
    expect(find.text('2026-09-06T21:46:34.682592'), findsNothing);
  });
}
