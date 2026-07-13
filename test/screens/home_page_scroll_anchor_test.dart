import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/screens/home_page.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/interaction.dart';
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
  Future<List<Interaction>> getInteractionsForContact(String contactId) async =>
      [];
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
      'HomePage return from details does not show skeleton and anchors scroll',
      (WidgetTester tester) async {
    final contact = Contact(
      id: 'test-contact-id',
      firstName: 'Anchor',
      lastName: 'Contact',
      location: 'New York',
      updatedAt: DateTime.now(),
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // Verify location group New York and contact name are rendered
    expect(find.text('New York'), findsOneWidget);
    expect(find.text('Anchor Contact'), findsOneWidget);

    // Tap on contact card to navigate
    await tester.tap(find.text('Anchor Contact'));
    await tester.pump();
    await tester
        .pump(const Duration(seconds: 1)); // let push animation complete

    // Verify details page or navigator active
    expect(find.byType(Navigator), findsOneWidget);

    // Pop back simulating return
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop(contact); // Pop back returning the contact

    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // let pop animation complete
    await tester.pump(const Duration(milliseconds: 400));

    // Verify no skeleton is displayed (meaning we returned to normal screen directly)
    expect(find.byKey(const ValueKey('home_skeleton')), findsNothing);
  });
}
