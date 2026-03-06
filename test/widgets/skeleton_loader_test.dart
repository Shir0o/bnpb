import 'package:bnpb/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SkeletonLoader wraps child in RepaintBoundary for performance', (
    WidgetTester tester,
  ) async {
    // Arrange: Create a SkeletonLoader with a simple child.
    // Use Directionality to provide required context without extra layers like MaterialApp.
    const childKey = Key('child');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SkeletonLoader(
          child: SizedBox(key: childKey, width: 100, height: 100),
        ),
      ),
    );

    // Act: Look for a RepaintBoundary that is a descendant of SkeletonLoader.
    final skeletonLoaderFinder = find.byType(SkeletonLoader);
    final repaintBoundaryFinder = find.descendant(
      of: skeletonLoaderFinder,
      matching: find.byType(RepaintBoundary),
    );

    // Assert: RepaintBoundary should be present to isolate the child paint layer.
    expect(
      repaintBoundaryFinder,
      findsOneWidget,
      reason:
          'SkeletonLoader must wrap its child in a RepaintBoundary to avoid repainting complex subtrees on every animation frame.',
    );
  });
}
