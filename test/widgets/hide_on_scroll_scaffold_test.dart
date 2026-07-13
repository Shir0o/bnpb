import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/widgets/hide_on_scroll_scaffold.dart';

void main() {
  group('HideOnScrollScaffold', () {
    testWidgets('shows the AppBar initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HideOnScrollScaffold(
            appBar: AppBar(title: const Text('Test')),
            body: ListView.builder(
              itemCount: 50,
              itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
            ),
          ),
        ),
      );

      // The AppBar title should be visible.
      expect(find.text('Test'), findsOneWidget);

      // The ClipRect wrapping the animated AppBar should have non-zero height.
      final clipRect = tester.widget<ClipRect>(find.byType(ClipRect).first);
      expect(clipRect, isNotNull);
      final clipRectBox = tester.getRect(find.byType(ClipRect).first);
      expect(clipRectBox.height, greaterThan(0));
    });

    testWidgets('hides AppBar when scrolling down', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HideOnScrollScaffold(
            appBar: AppBar(
              title: const Text('Test'),
              toolbarHeight: 56,
            ),
            body: ListView.builder(
              itemCount: 100,
              itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
            ),
          ),
        ),
      );

      // Verify initially visible.
      final initialRect = tester.getRect(find.byType(ClipRect).first);
      expect(initialRect.height, greaterThan(0));

      // Scroll down significantly.
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      // The ClipRect height should now be 0 (bar hidden).
      final hiddenRect = tester.getRect(find.byType(ClipRect).first);
      expect(hiddenRect.height, equals(0));
    });

    testWidgets('shows AppBar again when scrolling up', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HideOnScrollScaffold(
            appBar: AppBar(
              title: const Text('Test'),
              toolbarHeight: 56,
            ),
            body: ListView.builder(
              itemCount: 100,
              itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
            ),
          ),
        ),
      );

      // Scroll down to hide.
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      // Confirm hidden.
      final hiddenRect = tester.getRect(find.byType(ClipRect).first);
      expect(hiddenRect.height, equals(0));

      // Scroll up.
      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pumpAndSettle();

      // AppBar should be visible again.
      final shownRect = tester.getRect(find.byType(ClipRect).first);
      expect(shownRect.height, greaterThan(0));
    });

    testWidgets('passes through other Scaffold properties', (tester) async {
      final fab = FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HideOnScrollScaffold(
            appBar: AppBar(title: const Text('Test')),
            body: const SizedBox.expand(),
            floatingActionButton: fab,
            backgroundColor: Colors.red,
          ),
        ),
      );

      // FAB is present.
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Background colour is applied to the Scaffold.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.red);
    });

    testWidgets('works with non-scrollable body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HideOnScrollScaffold(
            appBar: AppBar(title: const Text('Static')),
            body: const Center(child: Text('Hello')),
          ),
        ),
      );

      // AppBar is visible.
      expect(find.text('Static'), findsOneWidget);
      final clipRect = tester.getRect(find.byType(ClipRect).first);
      expect(clipRect.height, greaterThan(0));
    });
  });
}
