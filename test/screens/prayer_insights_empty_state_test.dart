import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/screens/home_page.dart';

void main() {
  testWidgets('shows CTA when there are no prayer requests', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrayerInsightsEmptyState(
            onAddRequest: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Log prayer requests from a contact to receive reminders and celebrate answered prayers here.',
      ),
      findsOneWidget,
    );

    final addRequestButton =
        find.widgetWithText(FilledButton, 'Add a prayer request');
    expect(addRequestButton, findsOneWidget);

    await tester.tap(addRequestButton);
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
