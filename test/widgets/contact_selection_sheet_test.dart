import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/widgets/contact_selection_sheet.dart';
import 'package:bnpb/screens/add_contact_page.dart';
import 'package:bnpb/services/backup_service.dart';
import 'package:bnpb/services/reminder_coordinator.dart';
import 'package:bnpb/services/contact_search_service.dart';

class MockDBHelper extends Mock implements DBHelper {}

class MockBackupService extends Mock implements BackupService {}

class MockReminderCoordinator extends Mock implements ReminderCoordinator {}

class MockContactSearchService extends Mock implements ContactSearchService {}

void main() {
  late MockDBHelper mockDBHelper;
  late MockBackupService mockBackupService;
  late MockReminderCoordinator mockReminderCoordinator;
  late MockContactSearchService mockSearchService;

  setUpAll(() {
    registerFallbackValue(Contact(id: 'fake', firstName: 'Fake'));
    registerFallbackValue(<Contact>[]);
  });

  setUp(() {
    mockDBHelper = MockDBHelper();
    mockBackupService = MockBackupService();
    mockReminderCoordinator = MockReminderCoordinator();
    mockSearchService = MockContactSearchService();

    DBHelper.overrideForTest(mockDBHelper);
    BackupService.overrideForTest(mockBackupService);
    ReminderCoordinator.overrideForTest(mockReminderCoordinator);
  });

  tearDown(() {
    DBHelper.resetTestOverride();
    BackupService.overrideForTest(null);
    ReminderCoordinator.resetTestOverride();
  });

  testWidgets(
      'displays Create New Contact tile and handles creation & auto-selection',
      (
    WidgetTester tester,
  ) async {
    Contact? createdContact;

    // 1. Stub DBHelper and mock search service
    when(() => mockDBHelper.getContacts()).thenAnswer((_) async => [
          Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith'),
          if (createdContact != null) createdContact!,
        ]);
    when(() => mockDBHelper.getDistinctLocations()).thenAnswer((_) async => []);
    when(() => mockDBHelper.insertContact(any()))
        .thenAnswer((invocation) async {
      createdContact = invocation.positionalArguments[0] as Contact;
    });

    when(() => mockBackupService.exportBackup()).thenAnswer((_) async => null);
    when(() => mockReminderCoordinator.syncSignificantDates(any()))
        .thenAnswer((_) async {});

    when(() => mockSearchService.index(any())).thenReturn(null);
    when(() => mockSearchService.search(any())).thenAnswer((invocation) async {
      final query = invocation.positionalArguments[0] as String;
      if (query.isEmpty) {
        return [
          ContactMatch(
            contact: Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith'),
            score: 0,
          ),
        ];
      } else if (query == 'John Doe') {
        if (createdContact != null) {
          return [
            ContactMatch(contact: createdContact!, score: 1.0),
          ];
        }
        return [];
      }
      return [];
    });

    // 2. Pump ContactSelectionSheet inside a MaterialApp
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContactSelectionSheet(
            searchService: mockSearchService,
          ),
        ),
      ),
    );

    // Wait for the loading delay (400ms) to complete
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Verify existing contacts are displayed
    expect(find.text('Alice Smith'), findsOneWidget);

    // Verify "Create New Contact" tile is present
    expect(find.text('Create New Contact'), findsOneWidget);
    expect(find.text('Add a new person to your contacts'), findsOneWidget);

    // 3. Enter search query
    await tester.enterText(find.byType(TextField), 'John Doe');
    await tester.pump();

    // Verify the tile text updates to reflect search query
    expect(find.text("Create Contact 'John Doe'"), findsOneWidget);
    expect(find.text("Create and select 'John Doe'"), findsOneWidget);

    // 4. Tap on "Create Contact 'John Doe'"
    await tester.tap(find.text("Create Contact 'John Doe'"));
    // Settle the navigation animation pushing AddContactPage
    await tester.pumpAndSettle();

    // Verify we are now on the AddContactPage
    expect(find.byType(AddContactPage), findsOneWidget);

    // First name and last name should be pre-filled as "John" and "Doe"
    final textFormFields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(textFormFields[0].controller?.text, 'John');
    expect(textFormFields[2].controller?.text, 'Doe');

    // 5. Save the contact from AddContactPage
    // Tap Save button
    await tester.tap(find.text('Save'));
    // Let the async save database and reminder operations finish
    await tester.idle();

    // Rebuild and complete the pop navigation transition and selection sheet reload
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify that we popped back to ContactSelectionSheet
    expect(find.byType(AddContactPage), findsNothing);
    expect(find.byType(ContactSelectionSheet), findsOneWidget);

    // Verify John Doe is now in the list
    final johnDoeTile = find.widgetWithText(ListTile, 'John Doe');
    expect(johnDoeTile, findsOneWidget);

    final johnCheckbox = tester.widget<Checkbox>(
      find.descendant(
        of: johnDoeTile,
        matching: find.byType(Checkbox),
      ),
    );
    expect(johnCheckbox.value, isTrue);
  });
}
