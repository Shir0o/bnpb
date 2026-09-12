import 'dart:async';
import 'dart:convert';
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
import 'package:bnpb/services/ai/ai_services.dart';
import 'package:bnpb/widgets/log_interaction_sheet.dart';
import 'package:uuid/uuid.dart';
import '../repositories/mock_db_helper.dart';
import '../services/ai/_fake_pipeline_llm.dart';

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
    final List<PrayerRequest> filtered = prayerRequests
        .where((pr) => includeDeleted ? true : pr.deletedAt == null)
        .where((pr) => status == null ? true : pr.status == status)
        .toList();
    if (limit == null) return filtered;
    return filtered.take(limit).toList();
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
    AiServices().debugOverride();
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

    expect(find.text('NEEDS PRAYER'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('ANSWERED'), findsOneWidget);
    final answeredCardFinder = find.ancestor(
      of: find.text('ANSWERED'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: answeredCardFinder, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.text('ANSWERED'));
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsOneWidget);
  });

  testWidgets('HomePage renders dynamic header action buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Contacts'), findsOneWidget);
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

    expect(find.text('Follow-up suggestions'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.byType(LogInteractionSheet), findsOneWidget);
  });

  testWidgets('HomePage renders a confirmed routine with a sequence pill',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final contactId = const Uuid().v4();
    final key = '$contactId@@bible reading@@coffee';
    SharedPreferences.setMockInitialValues({
      'recurring_log.preferences': jsonEncode({
        key: {'confirmed': true},
      }),
    });

    Interaction reading(DateTime date, String notes) {
      return Interaction(
        id: date.day,
        participantIds: [contactId],
        occurredAt: date,
        summary: 'Bible reading',
        medium: 'Coffee',
        durationMinutes: 45,
        notes: notes,
      );
    }

    final contact = Contact(
      id: contactId,
      firstName: 'Timothy',
      lastName: 'Alvarez',
      updatedAt: now,
      interactions: [
        reading(today.subtract(const Duration(days: 21)), 'Psa. 115-116'),
        reading(today.subtract(const Duration(days: 14)), 'Psa. 117-118'),
        reading(today.subtract(const Duration(days: 7)), 'Psa. 119-120'),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Ready to log'), findsOneWidget);
    expect(find.text('Psa. 121\u2013122'), findsOneWidget);

    await tester.tap(find.text('Psa. 121\u2013122'));
    await tester.pumpAndSettle();

    expect(find.byType(LogInteractionSheet), findsOneWidget);
  });

  testWidgets(
      'HomePage asks to confirm a detected routine before suggesting it',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final contactId = const Uuid().v4();

    Interaction reading(DateTime date, String notes) {
      return Interaction(
        id: date.day,
        participantIds: [contactId],
        occurredAt: date,
        summary: 'Bible reading',
        medium: 'Coffee',
        durationMinutes: 45,
        notes: notes,
      );
    }

    final contact = Contact(
      id: contactId,
      firstName: 'Timothy',
      lastName: 'Alvarez',
      updatedAt: now,
      interactions: [
        reading(today.subtract(const Duration(days: 21)), 'Psa. 115-116'),
        reading(today.subtract(const Duration(days: 14)), 'Psa. 117-118'),
        reading(today.subtract(const Duration(days: 7)), 'Psa. 119-120'),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Routine detected'), findsOneWidget);
    expect(find.text('Psa. 121\u2013122'), findsNothing);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Psa. 121\u2013122'), findsOneWidget);
  });

  testWidgets(
      'HomePage falls back to AI for free-form scripture notes when AI is enabled',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final contactId = const Uuid().v4();
    final key = '$contactId@@bible reading@@in person';

    SharedPreferences.setMockInitialValues({
      'ai.features.enabled': true,
      'ai.features.scripture_ref_advancement': true,
      'recurring_log.preferences': jsonEncode({
        key: {'confirmed': true},
      }),
    });
    AiServices().debugOverride(
      llm: FakePipelineLlm('{"book":"Psa","start":117,"end":117}'),
    );

    Interaction reading(DateTime date) {
      return Interaction(
        id: date.day,
        participantIds: [contactId],
        occurredAt: date,
        summary: 'Bible reading',
        medium: 'In person',
        durationMinutes: 30,
        notes: 'Read psalm one-seventeen together',
      );
    }

    final contact = Contact(
      id: contactId,
      firstName: 'Joanna',
      lastName: 'Park',
      updatedAt: now,
      interactions: [
        reading(today.subtract(const Duration(days: 21))),
        reading(today.subtract(const Duration(days: 14))),
        reading(today.subtract(const Duration(days: 7))),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Ready to log'), findsOneWidget);
    expect(find.text('Psa. 118'), findsOneWidget);
  });

  testWidgets(
      'HomePage does not surface unresolved scripture notes when AI is disabled',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final contactId = const Uuid().v4();
    final key = '$contactId@@bible reading@@in person';

    SharedPreferences.setMockInitialValues({
      'recurring_log.preferences': jsonEncode({
        key: {'confirmed': true},
      }),
    });

    Interaction reading(DateTime date) {
      return Interaction(
        id: date.day,
        participantIds: [contactId],
        occurredAt: date,
        summary: 'Bible reading',
        medium: 'In person',
        durationMinutes: 30,
        notes: 'Read psalm one-seventeen together',
      );
    }

    final contact = Contact(
      id: contactId,
      firstName: 'Mark',
      lastName: 'Reyes',
      updatedAt: now,
      interactions: [
        reading(today.subtract(const Duration(days: 21))),
        reading(today.subtract(const Duration(days: 14))),
        reading(today.subtract(const Duration(days: 7))),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Ready to log'), findsNothing);
  });

  testWidgets('HomePage shows non-scripture routines without a sequence pill',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final contactId = const Uuid().v4();
    final key = '$contactId@@workout@@in person';

    SharedPreferences.setMockInitialValues({
      'recurring_log.preferences': jsonEncode({
        key: {'confirmed': true},
      }),
    });

    Interaction workout(DateTime date) {
      return Interaction(
        id: date.day,
        participantIds: [contactId],
        occurredAt: date,
        summary: 'Workout',
        medium: 'In person',
        durationMinutes: 30,
      );
    }

    final contact = Contact(
      id: contactId,
      firstName: 'Jordan',
      lastName: 'Lee',
      updatedAt: now,
      interactions: [
        workout(today.subtract(const Duration(days: 21))),
        workout(today.subtract(const Duration(days: 14))),
        workout(today.subtract(const Duration(days: 7))),
      ],
    );
    fakeDbHelper.contacts.add(contact);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Ready to log'), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
  });
}
