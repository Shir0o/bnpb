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

    testWidgets('renders candidates and allows selecting / deselecting', (
      tester,
    ) async {
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

      // Uncheck the first candidate. Newest-first sort puts Dinner (Sep 19)
      // above Lunch (Sep 17), so the first checkbox is Dinner.
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));
      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      expect(find.text('Import 1 Selected'), findsOneWidget);

      // Tap confirm button, then confirm the dialog.
      await tester.tap(find.text('Import 1 Selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
      await tester.pumpAndSettle();

      expect(confirmedCandidates, isNotNull);
      expect(confirmedCandidates!.length, 1);
      expect(confirmedCandidates!.first.fingerprint, 'fp1');
    });

    testWidgets('sorts newest-first', (tester) async {
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeTrackerStagingSheet(
              candidates: candidates,
              contacts: contacts,
              onConfirm: (_) {},
            ),
          ),
        ),
      );

      // First candidate row should be the newer Dinner.
      final firstSummary = tester
          .widget<Text>(find.text('Dinner - Boba').first)
          .data;
      expect(firstSummary, 'Dinner - Boba');

      // Checkbox order: Dinner first, then Lunch.
      final checkboxes = find.byType(Checkbox);
      final positions = [
        for (var i = 0; i < 2; i++) tester.getTopLeft(checkboxes.at(i)).dy,
      ];
      expect(positions[0], lessThan(positions[1]));
    });

    testWidgets('filters by contact chip', (tester) async {
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
        CandidateInteraction(
          fingerprint: 'fp3',
          occurredAt: DateTime(2025, 9, 20, 9, 0),
          durationMinutes: 30,
          activityName: 'Meeting',
          summary: 'Meeting - general',
          matchedContactIds: [],
          rawComment: 'general',
          selected: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeTrackerStagingSheet(
              candidates: candidates,
              contacts: contacts,
              onConfirm: (_) {},
            ),
          ),
        ),
      );

      // Enlarge viewport so the lazy list builds all items.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();

      // All three visible.
      expect(find.text('Lunch w/ Abel'), findsOneWidget);
      expect(find.text('Dinner - Boba'), findsOneWidget);
      expect(find.text('Meeting - general'), findsOneWidget);

      // Tap the Abel filter chip.
      await tester.tap(find.widgetWithText(FilterChip, 'Abel Smith'));
      await tester.pumpAndSettle();

      expect(find.text('Lunch w/ Abel'), findsOneWidget);
      expect(find.text('Dinner - Boba'), findsNothing);
      expect(find.text('Meeting - general'), findsNothing);

      // Tap Unassigned.
      await tester.tap(find.text('Unassigned'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting - general'), findsOneWidget);
      expect(find.text('Lunch w/ Abel'), findsNothing);
      expect(find.text('Dinner - Boba'), findsNothing);
    });

    testWidgets('allows committing a single item without importing all', (
      tester,
    ) async {
      final candidates = [
        CandidateInteraction(
          fingerprint: 'fp1',
          occurredAt: DateTime(2025, 9, 17, 11, 46),
          durationMinutes: 60,
          activityName: 'Lunch',
          summary: 'Lunch w/ Abel',
          matchedContactIds: ['c1'],
          rawComment: 'w/ Abel',
          selected: false,
        ),
        CandidateInteraction(
          fingerprint: 'fp2',
          occurredAt: DateTime(2025, 9, 19, 22, 16),
          durationMinutes: 46,
          activityName: 'Dinner',
          summary: 'Dinner - Boba',
          matchedContactIds: ['c2'],
          rawComment: 'Boba w/ Benji',
          selected: false,
        ),
      ];

      List<CandidateInteraction>? confirmed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeTrackerStagingSheet(
              candidates: candidates,
              contacts: contacts,
              onConfirm: (items) {
                confirmed = items;
              },
            ),
          ),
        ),
      );

      expect(find.text('Dinner - Boba'), findsOneWidget);
      expect(find.text('Lunch w/ Abel'), findsOneWidget);

      // Find the single-item commit button for Dinner (the first candidate)
      final importSingleBtns = find.byTooltip('Import this item');
      expect(importSingleBtns, findsNWidgets(2));

      await tester.tap(importSingleBtns.first);
      await tester.pumpAndSettle();

      expect(confirmed, isNotNull);
      expect(confirmed!.length, 1);
      expect(confirmed!.first.fingerprint, 'fp2');

      // Dinner is now removed from queue, Lunch remains
      expect(find.text('Dinner - Boba'), findsNothing);
      expect(find.text('Lunch w/ Abel'), findsOneWidget);
    });

    testWidgets('dismisses a single item and reports its fingerprint', (
      tester,
    ) async {
      final candidates = [
        CandidateInteraction(
          fingerprint: 'fp1',
          occurredAt: DateTime(2025, 9, 17, 11, 46),
          durationMinutes: 60,
          activityName: 'Lunch',
          summary: 'Lunch w/ Abel',
          matchedContactIds: ['c1'],
          rawComment: 'w/ Abel',
          selected: false,
        ),
        CandidateInteraction(
          fingerprint: 'fp2',
          occurredAt: DateTime(2025, 9, 19, 22, 16),
          durationMinutes: 46,
          activityName: 'Dinner',
          summary: 'Dinner - Boba',
          matchedContactIds: ['c2'],
          rawComment: 'Boba w/ Benji',
          selected: false,
        ),
      ];

      final dismissedFingerprints = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeTrackerStagingSheet(
              candidates: candidates,
              contacts: contacts,
              onConfirm: (_) {},
              onDismissCandidates: (fingerprints) {
                dismissedFingerprints.addAll(fingerprints);
              },
            ),
          ),
        ),
      );

      // Dismiss the first (newest, Dinner) item.
      final dismissBtns = find.byTooltip('Dismiss this item');
      expect(dismissBtns, findsNWidgets(2));
      await tester.tap(dismissBtns.first);
      await tester.pumpAndSettle();

      expect(dismissedFingerprints, ['fp2']);
      expect(find.text('Dinner - Boba'), findsNothing);
      expect(find.text('Lunch w/ Abel'), findsOneWidget);
    });

    testWidgets(
      'dismiss all unassigned requires confirmation and removes them',
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
            selected: false,
          ),
          CandidateInteraction(
            fingerprint: 'fp3',
            occurredAt: DateTime(2025, 9, 20, 9, 0),
            durationMinutes: 30,
            activityName: 'Meeting',
            summary: 'Meeting - general',
            matchedContactIds: [],
            rawComment: 'general',
            selected: false,
          ),
        ];

        final dismissedFingerprints = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TimeTrackerStagingSheet(
                candidates: candidates,
                contacts: contacts,
                onConfirm: (_) {},
                onDismissCandidates: (fingerprints) {
                  dismissedFingerprints.addAll(fingerprints);
                },
              ),
            ),
          ),
        );

        expect(find.text('Dismiss all unassigned'), findsOneWidget);

        // Cancel the confirmation dialog: nothing is dismissed.
        await tester.tap(find.text('Dismiss all unassigned'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(dismissedFingerprints, isEmpty);
        expect(find.text('Meeting - general'), findsOneWidget);

        // Confirm the dialog: unassigned item dismissed, assigned stays.
        await tester.tap(find.text('Dismiss all unassigned'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Dismiss'));
        await tester.pumpAndSettle();

        expect(dismissedFingerprints, ['fp3']);
        expect(find.text('Meeting - general'), findsNothing);
        expect(find.text('Lunch w/ Abel'), findsOneWidget);
      },
    );

    testWidgets('import all is gated behind confirmation', (tester) async {
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

      var confirmCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeTrackerStagingSheet(
              candidates: candidates,
              contacts: contacts,
              onConfirm: (_) => confirmCalls++,
            ),
          ),
        ),
      );

      // Cancel leaves everything in place.
      await tester.tap(find.text('Import 2 Selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(confirmCalls, 0);
      expect(find.text('Dinner - Boba'), findsOneWidget);

      // Confirm triggers onConfirm once.
      await tester.tap(find.text('Import 2 Selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
      await tester.pumpAndSettle();
      expect(confirmCalls, 1);
    });
  });
}
