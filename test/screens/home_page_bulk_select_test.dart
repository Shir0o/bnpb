import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/screens/home_page.dart';
import 'package:bnpb/widgets/people_card.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/reminder_service.dart';
import 'package:bnpb/services/security_service.dart';
import 'package:bnpb/services/backup_service.dart';
import '../../test/repositories/mock_db_helper.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockReminderService extends Mock implements ReminderService {}

class MockSecurityService extends Mock implements SecurityService {}

class MockBackupService extends Mock implements BackupService {}

class FakeDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  final List<Contact> updatedContacts = [];

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      contacts;

  @override
  Future<Map<PrayerRequestStatus, int>> getPrayerRequestCounts() async => {};

  @override
  Future<void> updateContact(Contact contact) async {
    updatedContacts.add(contact);
    final idx = contacts.indexWhere((c) => c.id == contact.id);
    if (idx != -1) {
      contacts[idx] = contact;
    }
  }
}

void main() {
  late MockGoogleDriveService mockGoogleDriveService;
  late MockReminderService mockReminderService;
  late MockSecurityService mockSecurityService;
  late MockBackupService mockBackupService;
  late FakeDBHelper fakeDbHelper;

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockGoogleDriveService = MockGoogleDriveService();
    when(() => mockGoogleDriveService.isInitializing).thenReturn(false);
    when(() => mockGoogleDriveService.onUserChanged)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockGoogleDriveService.currentUser)
        .thenAnswer((_) async => null);

    mockReminderService = MockReminderService();
    when(() => mockReminderService.isExactAlarmPermissionRelevant())
        .thenAnswer((_) async => false);
    when(() => mockReminderService.isExactAlarmOptInEnabled())
        .thenAnswer((_) async => false);

    mockSecurityService = MockSecurityService();
    when(() => mockSecurityService.hasPasscode())
        .thenAnswer((_) async => false);
    when(() => mockSecurityService.isBiometricEnabled())
        .thenAnswer((_) async => false);
    when(() => mockSecurityService.canUseBiometrics())
        .thenAnswer((_) async => false);

    mockBackupService = MockBackupService();
    when(() => mockBackupService.exportBackup()).thenAnswer((_) async => null);

    fakeDbHelper = FakeDBHelper();
    GoogleDriveService.overrideForTest(mockGoogleDriveService);
    ReminderService.overrideForTest(mockReminderService);
    SecurityService.overrideForTest(mockSecurityService);
    BackupService.overrideForTest(mockBackupService);
    DBHelper.overrideForTest(fakeDbHelper);
  });

  tearDown(() {
    GoogleDriveService.resetTestOverride();
    ReminderService.resetTestOverride();
    SecurityService.resetTestOverride();
    BackupService.overrideForTest(null);
    DBHelper.resetTestOverride();
  });

  testWidgets(
      'HomePage can enter bulk select mode and bulk edit contact locations',
      (WidgetTester tester) async {
    // Set screen size to avoid any off-screen tap warnings
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final contact1 = Contact(
      id: 'c1',
      firstName: 'Alice',
      lastName: 'Smith',
      location: 'New York',
      updatedAt: DateTime.now(),
    );
    final contact2 = Contact(
      id: 'c2',
      firstName: 'Bob',
      lastName: 'Jones',
      location: 'London',
      updatedAt: DateTime.now(),
    );
    fakeDbHelper.contacts.addAll([contact1, contact2]);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify groups New York and London are rendered
    expect(find.text('New York'), findsOneWidget);
    expect(find.text('London'), findsOneWidget);

    // Expand New York group
    final newYorkHeader = find.text('New York').first;
    await tester.tap(newYorkHeader);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Expand London group
    final londonHeader = find.text('London').first;
    await tester.tap(londonHeader);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify checklist button exists in AppBar and tap it to enter bulk select mode
    final bulkSelectBtn = find.byIcon(Icons.checklist_rounded);
    expect(bulkSelectBtn, findsOneWidget);
    await tester.tap(bulkSelectBtn);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify we are in select mode (should show "0 selected" and Select All / Deselect All / Edit Location buttons)
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byIcon(Icons.select_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.deselect), findsOneWidget);

    // Find cards precisely
    final aliceCard = find.byWidgetPredicate(
        (widget) => widget is PeopleCard && widget.contact.id == 'c1');
    final bobCard = find.byWidgetPredicate(
        (widget) => widget is PeopleCard && widget.contact.id == 'c2');

    expect(aliceCard, findsOneWidget);
    expect(bobCard, findsOneWidget);

    // Tap Alice to select her
    await tester.tap(aliceCard);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    // Tap Bob to select him too
    await tester.tap(bobCard);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // Tap Edit Location
    await tester.tap(find.byIcon(Icons.edit_location_alt_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Dialog should show up
    expect(find.text('Change Location'), findsOneWidget);
    expect(
        find.textContaining(
            'Enter a new location for the 2 selected contact(s).'),
        findsOneWidget);

    // Fill location
    await tester.enterText(find.byType(TextFormField), 'Paris');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    // Click Change
    await tester.tap(find.text('Change'));
    await tester.pump(); // Start change dialog dismiss
    await tester.pump(const Duration(
        milliseconds: 100)); // loading dialog shows up and performs updates
    await tester.pump(const Duration(
        milliseconds: 100)); // loading dialog dismiss and sets state
    await tester.pump(const Duration(milliseconds: 400));

    // Verify locations were updated in DBHelper
    expect(fakeDbHelper.updatedContacts.length, 2);
    expect(fakeDbHelper.updatedContacts[0].location, 'Paris');
    expect(fakeDbHelper.updatedContacts[1].location, 'Paris');
  });
}
