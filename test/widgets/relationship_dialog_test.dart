import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/widgets/relationship_dialog.dart';

void main() {
  final contactA = Contact(
    id: '1',
    firstName: 'Alice',
    lastName: 'Smith',
  );
  final contactB = Contact(
    id: '2',
    firstName: 'Bob',
    lastName: 'Jones',
  );

  Widget createDialog({
    Relationship? relationship,
    required Function(Relationship) onSave,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RelationshipDialog(
          currentContact: contactA,
          availableContacts: [contactB],
          relationship: relationship,
          onSave: onSave,
        ),
      ),
    );
  }

  testWidgets('Dialog defaults to Parent and shows correct sentence',
      (tester) async {
    Relationship? savedRelationship;
    await tester.pumpWidget(createDialog(
      onSave: (r) => savedRelationship = r,
    ));

    expect(find.text('Add Relationship'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    // Chip is selected?
    // We can check if dynamic text is correct.
    // Default is Parent.
    // Bob (Target) is the Parent of Alice (Source).
    // Logic: getTargetName() is Selected Contact (Bob).
    // getSourceName() is Current Contact (Alice).
    // Sentence: "Bob is the Parent of Alice"
    // Wait, let's check the code:
    // selectedContactId = widget.availableContacts.first.id (Bob)
    // selectedRole = 'Parent'
    // Text: '${getTargetName()} is the $role of ${getSourceName()}'

    expect(find.text('Bob Jones is the Parent of Alice Smith'), findsOneWidget);

    // Verify Save
    await tester.tap(find.text('Add'));
    expect(savedRelationship, isNotNull);
    expect(savedRelationship!.type, 'Parent');
    expect(savedRelationship!.targetContactId, '2');
  });

  testWidgets('Changing role updates text', (tester) async {
    await tester.pumpWidget(createDialog(
      onSave: (_) {},
    ));

    // Tap Child
    await tester.tap(find.text('Child'));
    await tester.pump();

    expect(find.text('Bob Jones is the Child of Alice Smith'), findsOneWidget);
  });

  testWidgets('Selecting Other shows text field and updates text',
      (tester) async {
    await tester.pumpWidget(createDialog(
      onSave: (_) {},
    ));

    // Tap Other
    await tester.tap(find.text('Other'));
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(2)); // Custom Type + Notes

    await tester.enterText(
        find.widgetWithText(TextField, 'Custom relationship type'), 'Mentor');
    await tester.pump();

    expect(find.text('Bob Jones is the Mentor of Alice Smith'), findsOneWidget);
  });

  testWidgets('Editing existing relationship pre-fills data', (tester) async {
    final existing = Relationship(
      id: 100,
      sourceContactId: '1',
      targetContactId: '2',
      type: 'Sibling',
      notes: 'Some notes',
    );

    Relationship? savedRelationship;
    await tester.pumpWidget(createDialog(
      relationship: existing,
      onSave: (r) => savedRelationship = r,
    ));

    expect(find.text('Edit Relationship'), findsOneWidget);
    expect(
        find.text('Bob Jones is the Sibling of Alice Smith'), findsOneWidget);
    expect(find.text('Some notes'), findsOneWidget);

    // Check Child chip is NOT selected, Sibling IS selected
    // Visual check hard, logical check:

    // Change to Spouse
    await tester.tap(find.text('Spouse'));
    await tester.pump();

    expect(find.text('Bob Jones is the Spouse of Alice Smith'), findsOneWidget);

    await tester.tap(find.text('Save'));
    expect(savedRelationship!.type, 'Spouse');
    expect(savedRelationship!.id, 100);
  });
}
