import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/backup_service.dart';
import 'package:bnpb/widgets/contact_multi_select.dart';
import 'package:bnpb/widgets/quick_create_contact_dialog.dart';

class MockDBHelper extends Mock implements DBHelper {}

class MockBackupService extends Mock implements BackupService {}

void main() {
  late MockDBHelper mockDBHelper;
  late MockBackupService mockBackupService;

  setUpAll(() {
    registerFallbackValue(Contact(id: 'fake', firstName: 'Fake'));
  });

  setUp(() {
    mockDBHelper = MockDBHelper();
    mockBackupService = MockBackupService();
    DBHelper.overrideForTest(mockDBHelper);
    BackupService.overrideForTest(mockBackupService);
  });

  tearDown(() {
    DBHelper.resetTestOverride();
    BackupService.overrideForTest(null);
  });

  testWidgets(
      'ContactMultiSelect allows quick creating a contact when search is empty',
      (tester) async {
    Contact? created;
    when(() => mockDBHelper.insertContact(any()))
        .thenAnswer((invocation) async {
      created = invocation.positionalArguments[0] as Contact;
    });
    when(() => mockBackupService.exportBackup()).thenAnswer((_) async => null);

    final contacts = [
      Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith'),
    ];

    List<String>? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedResult = await ContactMultiSelect.show(
                  context,
                  contacts: contacts,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Alice Smith'), findsOneWidget);

    // Search for someone nonexistent
    await tester.enterText(find.byType(TextField), 'Bob Builder');
    await tester.pumpAndSettle();

    expect(find.text('No matching contacts found'), findsOneWidget);
    expect(find.text("Quick Create 'Bob Builder'"), findsOneWidget);

    // Tap Quick Create button
    await tester.tap(find.text("Quick Create 'Bob Builder'"));
    await tester.pumpAndSettle();

    expect(find.byType(QuickCreateContactDialog), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Builder'), findsOneWidget);

    // Save
    await tester.tap(find.text('Create & Select'));
    await tester.idle();

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(created, isNotNull);
    expect(created!.firstName, 'Bob');
    expect(created!.lastName, 'Builder');

    // Tap Done
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult, contains(created!.id));
  });
}
