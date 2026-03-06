import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/screens/macos/prayer_diary_entry.dart';

void main() {
  group('PrayerDiaryEntry', () {
    final request = PrayerRequest(
      id: 1,
      participantIds: ['c1'],
      description: 'Test prayer request',
      status: PrayerRequestStatus.pending,
      requestedAt: DateTime(2023, 10, 24, 8, 30),
    );

    final contact = Contact(id: 'c1', firstName: 'John', lastName: 'Doe');

    testWidgets('renders correctly in view mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrayerDiaryEntry(
              request: request,
              contacts: [contact],
              isEditing: false,
              onEditStart: () {},
              onEditSave: (_) {},
              onEditCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test prayer request'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('8:30 AM'), findsOneWidget);
      // Edit button is in the tree (opacity 0), so it findsOneWidget
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('triggers onEditStart on double tap', (tester) async {
      bool editStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrayerDiaryEntry(
              request: request,
              contacts: [contact],
              isEditing: false,
              onEditStart: () {
                editStarted = true;
              },
              onEditSave: (_) {},
              onEditCancel: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PrayerDiaryEntry));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(PrayerDiaryEntry));
      await tester.pumpAndSettle();

      expect(editStarted, isTrue);
    });

    testWidgets('renders correctly in edit mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrayerDiaryEntry(
              request: request,
              contacts: [contact],
              isEditing: true, // Edit mode ON
              onEditStart: () {},
              onEditSave: (_) {},
              onEditCancel: () {},
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Test prayer request'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('triggers onEditSave with updated request', (tester) async {
      PrayerRequest? savedRequest;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrayerDiaryEntry(
              request: request,
              contacts: [contact],
              isEditing: true,
              onEditStart: () {},
              onEditSave: (req) {
                savedRequest = req;
              },
              onEditCancel: () {},
            ),
          ),
        ),
      );

      // Edit text
      await tester.enterText(find.byType(TextField), 'Updated prayer request');
      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(savedRequest, isNotNull);
      expect(savedRequest!.description, 'Updated prayer request');
    });
  });
}
