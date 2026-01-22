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
    expect(find.byKey(const Key('child1')), findsOneWidget); // Offstage but present in tree

    // Check Offstage status
    final offstageFinder = find.ancestor(of: find.byKey(const Key('child1')), matching: find.byType(Offstage));
    final Offstage offstage = tester.widget(offstageFinder);
    expect(offstage.offstage, isTrue);

    // Tap to expand
    await tester.tap(find.text('Test Title'));
    await tester.pump(); // Start animation
    await tester.pump(const Duration(milliseconds: 200)); // Mid animation

    // Should be visible (offstage false)
    final Offstage offstageExpanded = tester.widget(offstageFinder);
    expect(offstageExpanded.offstage, isFalse);

    // Check for RepaintBoundary
    // We expect NO RepaintBoundary around the child content initially (before optimization)
    // The child content is inside a Column inside Padding inside TickerMode inside Offstage.
    // However, _buildChildren wraps 'child' (result) in ClipRect -> Align.
    // So if RepaintBoundary is added, it will be around 'child'.

    final alignFinder = find.ancestor(of: offstageFinder, matching: find.byType(Align));
    expect(alignFinder, findsOneWidget);

    final align = tester.widget<Align>(alignFinder);
    final childOfAlign = align.child;

    // Verify it IS a RepaintBoundary
    expect(childOfAlign.runtimeType, RepaintBoundary);

    await tester.pumpAndSettle();
  });
}
