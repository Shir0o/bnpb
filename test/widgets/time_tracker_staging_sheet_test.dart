import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/widgets/time_tracker_staging_sheet.dart';

void main() {
  group('TimeTrackerStagingSheet', () {
    final contacts = [
      Contact(id: 'c1', firstName: 'Abel', lastName: 'Smith'),
      Contact(id: 'c2', firstName: 'Benji', lastName: 'Lee'),
    ];

    testWidgets('renders candidates and allows selecting / deselecting',
        (tester) async {
      final candidates = [
        CandidateInteraction(
          fingerprint: 'fp1',
          occurredAt: DateTime(2025, 9, 17, 11, 46),
          durationMinutes: 60,
          activityName: 'Lunch',
          summary: 'Lunch w/ Abel',
          matchedContactIds: ['c1'],
          rawComment: 'w/ Abel',
          selected: true,
        ),
        CandidateInteraction(
          fingerprint: 'fp2',
          occurredAt: DateTime(2025, 9, 19, 22, 16),
          durationMinutes: 46,
          activityName: 'Dinner',
          summary: 'Dinner - Boba',
          matchedContactIds: ['c2'],
          rawComment: 'Boba w/ Benji',
          selected: true,
        ),
      ];

      List<CandidateInteraction>? confirmedCandidates;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeTrackerStagingSheet(
              candidates: candidates,
              contacts: contacts,
              onConfirm: (selected) {
                confirmedCandidates = selected;
              },
            ),
          ),
        ),
      );

      expect(find.text('Time Tracker Staging Queue'), findsOneWidget);
      expect(find.text('Lunch w/ Abel'), findsOneWidget);
      expect(find.text('Dinner - Boba'), findsOneWidget);
      expect(find.text('Import 2 Selected'), findsOneWidget);

      // Uncheck the first candidate
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));
      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      expect(find.text('Import 1 Selected'), findsOneWidget);

      // Tap confirm button
      await tester.tap(find.text('Import 1 Selected'));
      await tester.pumpAndSettle();

      expect(confirmedCandidates, isNotNull);
      expect(confirmedCandidates!.length, 1);
      expect(confirmedCandidates!.first.fingerprint, 'fp2');
    });
  });
}
