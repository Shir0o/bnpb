import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/widgets/interaction_timeline_tile.dart';

void main() {
  testWidgets('InteractionTimelineTile renders without IntrinsicHeight',
      (WidgetTester tester) async {
    final interaction = Interaction(
      id: 1,
      occurredAt: DateTime(2023, 10, 26, 10, 30),
      summary: 'Test Interaction',
      medium: 'in_person',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractionTimelineTile(
            interaction: interaction,
            isFirst: false,
            isLast: false,
            displayNameResolver: (id) => 'John Doe',
          ),
        ),
      ),
    );

    expect(find.byType(InteractionTimelineTile), findsOneWidget);
    expect(find.text('Test Interaction'), findsOneWidget);
    expect(find.text('In-person'), findsOneWidget);

    // Verify absence of IntrinsicHeight within the tile
    expect(
      find.descendant(
        of: find.byType(InteractionTimelineTile),
        matching: find.byType(IntrinsicHeight),
      ),
      findsNothing,
    );

    // Verify presence of Stack within the tile
    expect(
      find.descendant(
        of: find.byType(InteractionTimelineTile),
        matching: find.byType(Stack),
      ),
      findsWidgets, // Might find more than one if nested, but at least one.
    );
  });

  testWidgets('InteractionTimelineTile triggers callbacks',
      (WidgetTester tester) async {
    bool tapped = false;
    bool edited = false;
    bool deleted = false;

    final interaction = Interaction(
      id: 1,
      occurredAt: DateTime.now(),
      summary: 'Test Callback',
      medium: 'call',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractionTimelineTile(
            interaction: interaction,
            isFirst: true,
            isLast: true,
            displayNameResolver: (id) => 'John',
            onTap: () => tapped = true,
            onEdit: () => edited = true,
            onDelete: () => deleted = true,
            isEditing: true, // Show edit buttons
          ),
        ),
      ),
    );

    // Tap main tile
    await tester.tap(find.text('Test Callback'));
    expect(tapped, true);

    // Tap edit button
    await tester.tap(find.byIcon(Icons.edit_outlined));
    expect(edited, true);

    // Tap delete button
    await tester.tap(find.byIcon(Icons.delete_outline));
    expect(deleted, true);
  });
}
