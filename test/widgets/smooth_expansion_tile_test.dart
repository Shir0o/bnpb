import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/widgets/smooth_expansion_tile.dart';

void main() {
  testWidgets('SmoothExpansionTile renders children and toggles expansion', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothExpansionTile(
            title: const Text('Test Title'),
            children: [
              Container(height: 100, color: Colors.red, key: const Key('child1')),
            ],
          ),
        ),
      ),
    );

    // Initially collapsed
    expect(find.text('Test Title'), findsOneWidget);
    // Optimized behavior: Child is NOT in the tree initially
    expect(find.byKey(const Key('child1')), findsNothing);

    // Tap to expand
    await tester.tap(find.text('Test Title'));
    await tester.pump(); // Start animation (setState)

    // Now child should be built
    expect(find.byKey(const Key('child1')), findsOneWidget);

    // Check for RepaintBoundary
    // We removed the RepaintBoundary from SmoothExpansionTile because it caused memory issues for large lists.
    // The child should NOT be wrapped in RepaintBoundary by the tile itself.
    // We check that there is no RepaintBoundary between the Align (animation wrapper) and the content.
    final alignFinder = find.byType(Align);
    final repaintBoundaryInAlign = find.descendant(of: alignFinder, matching: find.byType(RepaintBoundary));

    expect(repaintBoundaryInAlign, findsNothing);

    await tester.pumpAndSettle();
  });
}
