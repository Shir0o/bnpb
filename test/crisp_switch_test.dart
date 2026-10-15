import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/widgets/crisp_switch.dart';

void main() {
  group('CrispSwitch accessibility and interaction', () {
    testWidgets('renders with minimum 44x44 touch target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CrispSwitch(
                value: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(CrispSwitch));
      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, greaterThanOrEqualTo(44.0));
    });

    testWidgets('supports custom semanticLabel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CrispSwitch(
              value: true,
              onChanged: (_) {},
              semanticLabel: 'Dark mode',
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Dark mode'),
        findsOneWidget,
      );
    });

    testWidgets('toggles on tap', (tester) async {
      bool currentVal = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CrispSwitch(
                value: currentVal,
                onChanged: (val) => setState(() => currentVal = val),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CrispSwitch));
      await tester.pumpAndSettle();
      expect(currentVal, isTrue);
    });

    testWidgets('toggles on Space and Enter keys', (tester) async {
      bool currentVal = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CrispSwitch(
                focusNode: focusNode,
                autofocus: true,
                value: currentVal,
                onChanged: (val) => setState(() => currentVal = val),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      // Send Space key
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(currentVal, isTrue);

      // Send Enter key
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(currentVal, isFalse);

      focusNode.dispose();
    });

    testWidgets('respects disableAnimations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: CrispSwitch(
                value: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(animatedContainer.duration, Duration.zero);
    });
  });
}
