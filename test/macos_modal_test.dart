import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/widgets/macos_modal.dart';

void main() {
  group('showMacModal', () {
    testWidgets('renders dialog with FocusScope, Dialog and BackdropFilter',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMacModal(
                context,
                builder: (ctx) => const Text('Modal Body Content'),
              ),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Modal Body Content'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(FocusScope), findsAtLeastNWidgets(1));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('dismisses on Escape key', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMacModal(
                context,
                builder: (ctx) => const Text('Dismissible Modal'),
              ),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.text('Dismissible Modal'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Dismissible Modal'), findsNothing);
    });

    testWidgets('wraps overflowing content in SingleChildScrollView',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMacModal(
                context,
                builder: (ctx) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(100, (i) => Text('Row item $i')),
                ),
              ),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // No overflow exception thrown
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));
      expect(find.text('Row item 0'), findsOneWidget);
    });

    testWidgets('respects disableAnimations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMacModal(
                  context,
                  builder: (ctx) => const Text('No animation modal'),
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      // With Duration.zero, pumps immediately without needing pumpAndSettle
      await tester.pump();
      expect(find.text('No animation modal'), findsOneWidget);
    });
  });
}
