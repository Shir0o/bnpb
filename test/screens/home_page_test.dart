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
import 'package:bnpb/services/contact_service.dart';
import 'package:bnpb/widgets/log_interaction_sheet.dart';
import 'package:uuid/uuid.dart';
import '../repositories/mock_db_helper.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockReminderService extends Mock implements ReminderService {}

class MockSecurityService extends Mock implements SecurityService {}

class FakeDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  final List<PrayerRequest> prayerRequests = [];
  final List<Interaction> interactions = [];
  final Map<PrayerRequestStatus, int> counts = {
    PrayerRequestStatus.pending: 0,
    PrayerRequestStatus.answered: 0,
    PrayerRequestStatus.archived: 0,
  };

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return contacts;
  }

  @override
  Future<Map<PrayerRequestStatus, int>> getPrayerRequestCounts() async {
    return counts;
  }

  @override
  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    Iterable<PrayerRequest> filtered = prayerRequests;
    if (!includeDeleted) {
      filtered = filtered.where((pr) => pr.deletedAt == null);
    }
    if (status != null) {
      filtered = filtered.where((pr) => pr.status == status);
    }
    List<PrayerRequest> list = filtered.toList();
    if (limit != null) {
      list = list.take(limit).toList();
    }
    return list;
  }

  @override
  Future<List<Interaction>> getPrayerFocusInteractions({int? limit}) async {
    return interactions;
  }
}

void main() {
  late MockGoogleDriveService mockGoogleDriveService;
  late MockReminderService mockReminderService;
  late MockSecurityService mockSecurityService;
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

    fakeDbHelper = FakeDBHelper();

    GoogleDriveService.overrideForTest(mockGoogleDriveService);
    ReminderService.overrideForTest(mockReminderService);
    SecurityService.overrideForTest(mockSecurityService);
    DBHelper.overrideForTest(fakeDbHelper);
    ContactService().clearCache();
  });

  tearDown(() {
    ContactService().clearCache();
    GoogleDriveService.resetTestOverride();
    ReminderService.resetTestOverride();
    SecurityService.resetTestOverride();
    DBHelper.resetTestOverride();
  });

  testWidgets(
      'HomePage renders prayer insights count cards and navigates to PrayerDiaryPage',
      (WidgetTester tester) async {
    final contactId = const Uuid().v4();
    final contact = Contact(
      id: contactId,
      firstName: 'John',
      lastName: 'Doe',
      updatedAt: DateTime.now(),
    );
    fakeDbHelper.contacts.add(contact);

    final request = PrayerRequest(
      id: 1,
      participantIds: [contactId],
      description: 'Heal from sickness',
      status: PrayerRequestStatus.answered,
      requestedAt: DateTime.now().subtract(const Duration(days: 5)),
      answeredAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    fakeDbHelper.prayerRequests.add(request);
    fakeDbHelper.counts[PrayerRequestStatus.answered] = 1;
    fakeDbHelper.counts[PrayerRequestStatus.pending] = 3;

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // Verify it renders the Needs prayer count and label
    expect(find.text('NEEDS PRAYER'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Verify it renders the Answered count and label
    expect(find.text('ANSWERED'), findsOneWidget);
    final answeredCardFinder = find.ancestor(
      of: find.text('ANSWERED'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: answeredCardFinder, matching: find.text('1')),
      findsOneWidget,
    );

    // Tap Answered card
    await tester.tap(find.text('ANSWERED'));
    await tester.pumpAndSettle();

    // Verify PrayerDiaryPage is shown (can find filter chip)
    expect(find.text('Archived'), findsOneWidget);
  });

  testWidgets('HomePage renders dynamic header action buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // Verify Contacts title is present
    expect(find.text('Contacts'), findsOneWidget);

    // Verify the buttons are found by tooltips
    expect(find.byTooltip('Prayer Lists'), findsOneWidget);
    expect(find.byTooltip('Prayer Diary'), findsOneWidget);
    expect(find.byTooltip('Backup and Restore'), findsOneWidget);
    expect(find.byTooltip('Export'), findsOneWidget);
  });

  testWidgets(
      'HomePage renders follow-up suggestion cards with priority badges and log button',
      (WidgetTester tester) async {
    final contactId = const Uuid().v4();
    final contact = Contact(
      id: contactId,
      firstName: 'Jane',
      lastName: 'Smith',
      updatedAt: DateTime.now(),
      interactions: [
        Interaction(
          id: 1,
          participantIds: [contactId],
          occurredAt: DateTime.now().subtract(const Duration(days: 65)),
          summary: 'Met for coffee',
          medium: 'In Person',
        ),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // Verify Follow-up suggestions header & recommendation items
    expect(find.text('Follow-up suggestions'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);

    // Tap Log button
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    // Verify LogInteractionSheet opens
    expect(find.byType(LogInteractionSheet), findsOneWidget);
  });

  testWidgets(
      'HomePage renders Ready to log interaction suggestion card with sequence pills',
      (WidgetTester tester) async {
    final contactId = const Uuid().v4();
    final contact = Contact(
      id: contactId,
      firstName: 'Timothy',
      lastName: 'Alvarez',
      updatedAt: DateTime.now(),
      interactions: [
        Interaction(
          id: 10,
          participantIds: [contactId],
          occurredAt: DateTime.now().subtract(const Duration(days: 2)),
          summary: 'Bible reading',
          medium: 'Coffee',
          durationMinutes: 45,
          notes: 'PSA 115–116',
        ),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // Verify Ready to log card is rendered
    expect(find.text('Ready to log'), findsOneWidget);
    expect(find.text('Timothy Alvarez · 45 min'), findsOneWidget);
    expect(find.text('Psa. 117–118'), findsOneWidget);

    // Tap the Ready to log tile
    await tester.tap(find.text('Psa. 117–118'));
    await tester.pumpAndSettle();

    // Verify LogInteractionSheet opens
    expect(find.byType(LogInteractionSheet), findsOneWidget);
  });

  testWidgets(
      'HomePage shows the "is not adding up" review alert and opens the Review screen',
      (WidgetTester tester) async {
    final contactId = const Uuid().v4();
    final now = DateTime.now();
    final inMonth = now.day > 1 ? now.day - 1 : 1;
    final contact = Contact(
      id: contactId,
      firstName: 'Mara',
      lastName: 'Lopez',
      updatedAt: now,
      interactions: [
        Interaction(
          id: 1,
          participantIds: [contactId],
          occurredAt: DateTime(now.year, now.month, inMonth),
          summary: 'Coffee',
          medium: 'In Person',
        ),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // No one reached regular contact this month → attention alert shows.
    expect(find.textContaining('is not adding up'), findsOneWidget);
    expect(find.textContaining('needing attention'), findsOneWidget);

    // Tapping the alert opens the Review screen.
    await tester.tap(find.textContaining('is not adding up'));
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget);
  });
}
