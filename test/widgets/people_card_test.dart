import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/widgets/people_card.dart';
import 'package:bnpb/models/contact.dart';

void main() {
  testWidgets('PeopleCard uses Clip.none and explicit InkWell borderRadius',
      (WidgetTester tester) async {
    final contact = Contact(
      id: '1',
      firstName: 'John',
      lastName: 'Doe',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeopleCard(contact: contact),
        ),
      ),
    );

    // Verify Card properties
    final cardFinder = find.byType(Card);
    expect(cardFinder, findsOneWidget);
    final card = tester.widget<Card>(cardFinder);

    // DESIRED STATE: clipBehavior is null (default) which means Clip.none behavior without explicit clip setting
    expect(card.clipBehavior, null,
        reason: 'Card should use default clip behavior (none) for performance');

    // Verify InkWell properties
    final inkWellFinder = find.byType(InkWell);
    expect(inkWellFinder, findsOneWidget);
    final inkWell = tester.widget<InkWell>(inkWellFinder);

    // DESIRED STATE: borderRadius is set to match Card shape
    expect(inkWell.borderRadius, BorderRadius.circular(16),
        reason: 'InkWell should have explicit borderRadius');
  });
}
