import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/screens/contact_details_page.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/relationship.dart';

// Fake implementations
class FakeContactService extends Fake implements ContactService {
  final List<Interaction> interactions;

  FakeContactService({this.interactions = const []});

  @override
  bool hasCachedInteractions(String contactId) => false;

  @override
  Future<List<Interaction>> getInteractions(String contactId,
      {bool forceRefresh = false}) async {
    return interactions;
  }
}

class FakeDBHelper extends Fake implements DBHelper {
  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
  }) async {
    return [];
  }

  @override
  Future<List<String>> getAllTags() async {
    return [];
  }

  @override
  Future<List<Relationship>> getRelationshipsForContact(String contactId) async {
    return [];
  }
}

void main() {
  testWidgets('Timeline tile renders with correct CrossAxisAlignment.stretch',
      (WidgetTester tester) async {
    // Setup
    final interaction = Interaction(
      id: 1,
      occurredAt: DateTime.now(),
      summary: 'Test Interaction',
      medium: 'in_person',
      participantIds: ['1'],
    );

    final contact = Contact(
      id: '1',
      firstName: 'John',
      interactions: [interaction],
    );

    // Pump widget
    await tester.pumpWidget(
      MaterialApp(
        home: ContactDetailsPage(
          contact: contact,
          onDelete: () async {},
          contactService: FakeContactService(interactions: [interaction]), // Pass interactions
          dbHelper: FakeDBHelper(),
        ),
      ),
    );

    // Wait for initial load (skeleton)
    // Advance time by 1 second to finish the initial load delay (750ms).
    // SkeletonLoader animation is infinite, so pumpAndSettle would timeout.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(); // Frame for setState

    // Find the timeline tile.

    final sizedBoxFinder = find.byWidgetPredicate((widget) {
      return widget is SizedBox && widget.width == 48;
    });

    expect(sizedBoxFinder, findsOneWidget);

    final rowFinder = find.ancestor(
      of: sizedBoxFinder,
      matching: find.byType(Row),
    );

    expect(rowFinder, findsOneWidget);

    final row = tester.widget<Row>(rowFinder);

    // Assert
    expect(row.crossAxisAlignment, CrossAxisAlignment.stretch,
        reason: 'Timeline row must use stretch to ensure connecting lines are drawn correctly');

    // Also verify the child alignment is correct (Align topCenter instead of Center)
    final alignFinder = find.descendant(of: sizedBoxFinder, matching: find.byType(Align));
    expect(alignFinder, findsOneWidget);
    final align = tester.widget<Align>(alignFinder);
    expect(align.alignment, Alignment.topCenter);
  });
}
