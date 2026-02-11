import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/screens/contact_details_page.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:bnpb/widgets/contact_details_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:intl/date_symbol_data_local.dart';

class MockContactService extends Mock implements ContactService {}

class MockDBHelper extends Mock implements DBHelper {}

void main() {
  late MockContactService mockContactService;
  late MockDBHelper mockDBHelper;

  // Define fallback values
  final fallbackContact = Contact(
    id: 'fallback',
    firstName: 'Fallback',
    interactions: [],
  );

  final fallbackInteraction = Interaction(
    occurredAt: DateTime.now(),
    summary: 'fallback',
    medium: 'fallback',
  );

  final fallbackRelationship = Relationship(
    sourceContactId: 'fallback',
    targetContactId: 'fallback',
    type: 'fallback',
  );

  setUp(() async {
    // Initialize date formatting for tests
    await initializeDateFormatting('en_US', null);

    mockContactService = MockContactService();
    mockDBHelper = MockDBHelper();

    registerFallbackValue(fallbackContact);
    registerFallbackValue(fallbackInteraction);
    registerFallbackValue(fallbackRelationship);
  });

  testWidgets('ContactDetailsPage renders contact details correctly',
      (WidgetTester tester) async {
    debugPrint('START: Test Method Started');
    try {
      // 1. Prepare Test Data
      final contact = Contact(
        id: '123',
        firstName: 'John',
        lastName: 'Doe',
        nickname: 'Johnny',
        location: 'New York',
        notes: 'Some notes',
        interactions: [],
      );

      // 2. Setup Stubs with specific arguments to ensure matching

      // ContactService Stubs
      when(() => mockContactService.hasCachedInteractions('123'))
          .thenReturn(false);
      when(() => mockContactService.hasCachedInteractions(any()))
          .thenReturn(false);

      when(() => mockContactService.getInteractions('123',
              forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => []);
      when(() => mockContactService.getInteractions(any(),
              forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => []);

      // DBHelper Stubs
      when(() => mockDBHelper.getContacts()).thenAnswer((_) async => []);
      when(() => mockDBHelper.getContacts(contactId: any(named: 'contactId')))
          .thenAnswer((_) async => []);

      when(() => mockDBHelper.getAllTags()).thenAnswer((_) async => []);

      when(() => mockDBHelper.getRelationshipsForContact('123'))
          .thenAnswer((_) async => []);
      when(() => mockDBHelper.getRelationshipsForContact(any()))
          .thenAnswer((_) async => []);

      debugPrint('STEP: Stubs Setup Complete');

      // 3. Build Widget
      await tester.pumpWidget(
        MaterialApp(
          home: ContactDetailsPage(
            contact: contact,
            onDelete: () async {},
            contactService: mockContactService,
            dbHelper: mockDBHelper,
          ),
        ),
      );
      debugPrint('STEP: Widget Pumped');

      // 4. Verification steps

      // Initial load should show loading skeleton, NOT CircularProgressIndicator
      expect(find.byType(ContactDetailsSkeleton), findsOneWidget);

      // Wait for all animations and futures to settle
      await tester.pumpAndSettle();
      debugPrint('STEP: Widget Settled');

      // Verify fields are populated
      expect(find.text('John Doe'), findsAtLeastNWidgets(1));
      expect(find.text('New York'), findsOneWidget); // Location
      expect(find.text('Some notes'), findsOneWidget);
      expect(find.textContaining('Johnny'), findsOneWidget);

      // Verify that we are NOT in edit mode (edit icon should be present)
      expect(find.byIcon(Icons.edit), findsOneWidget);
    } catch (e, stack) {
      debugPrint('ERROR: Test Failed with exception: $e');
      debugPrint('STACK: $stack');
      rethrow;
    }
  });
}
