import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/screens/settings_page.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/notification_preference.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/reminder_service.dart';
import 'package:bnpb/services/security_service.dart';
import '../../test/repositories/mock_db_helper.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockReminderService extends Mock implements ReminderService {}

class MockSecurityService extends Mock implements SecurityService {}

class FakeDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  final List<NotificationPreference> preferences = [];
  final List<InteractionDuplicateGroup> duplicateGroups = [];
  int deDuplicateResult = 0;

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      contacts;

  @override
  Future<NotificationPreference?> getNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    for (final p in preferences) {
      if (p.scopeType == scopeType &&
          p.scopeId == scopeId &&
          p.channel == channel) {
        return p;
      }
    }
    return null;
  }

  @override
  Future<NotificationPreference> upsertNotificationPreference(
    NotificationPreference preference,
  ) async {
    preferences.removeWhere(
      (p) =>
          p.scopeType == preference.scopeType &&
          p.scopeId == preference.scopeId &&
          p.channel == preference.channel,
    );
    final saved = preference.copyWith(id: preferences.length + 1);
    preferences.add(saved);
    return saved;
  }

  @override
  Future<List<NotificationPreference>> getNotificationPreferences({
    NotificationScopeType? scopeType,
  }) async {
    if (scopeType != null) {
      return preferences.where((p) => p.scopeType == scopeType).toList();
    }
    return preferences;
  }

  @override
  Future<List<InteractionDuplicateGroup>> findDuplicateInteractions() async =>
      duplicateGroups;

  @override
  Future<int> deDuplicateInteractions() async => deDuplicateResult;
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
  });

  tearDown(() {
    GoogleDriveService.resetTestOverride();
    ReminderService.resetTestOverride();
    SecurityService.resetTestOverride();
    DBHelper.resetTestOverride();
  });

  testWidgets(
      'SettingsPage deduplicate run dry run shows detailed proposed changes',
      (WidgetTester tester) async {
    final contact1 =
        Contact(id: 'pid-1', firstName: 'Alice', updatedAt: DateTime.now());
    final contact2 =
        Contact(id: 'pid-2', firstName: 'Bob', updatedAt: DateTime.now());
    fakeDbHelper.contacts.addAll([contact1, contact2]);

    final occurredAt = DateTime(2026, 6, 2, 11, 0, 0);
    final primary = Interaction(
      id: 1,
      syncId: 'sync-1',
      occurredAt: occurredAt,
      summary: 'Coffee Chat',
      medium: 'in_person',
      location: '',
      attachments: const [],
      markForPrayer: false,
      notes: 'Initial primary notes',
      participantIds: ['pid-1'],
      updatedAt: DateTime.now().toUtc(),
    );
    final duplicate = Interaction(
      id: 2,
      syncId: 'sync-2',
      occurredAt: occurredAt,
      summary: 'Coffee Chat',
      medium: 'in_person',
      location: 'Starbucks',
      attachments: const [],
      markForPrayer: true,
      notes: 'Different notes',
      participantIds: ['pid-1', 'pid-2'],
      updatedAt: DateTime.now().toUtc(),
    );

    final group = InteractionDuplicateGroup(
      primary: primary,
      duplicates: [duplicate],
    );
    fakeDbHelper.duplicateGroups.add(group);
    fakeDbHelper.deDuplicateResult = 1;

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Scroll and click the Deduplicate button
    final deDupTile = find
        .byIcon(Icons.cleaning_services_outlined, skipOffstage: false)
        .first;
    expect(deDupTile, findsOneWidget);
    await tester.scrollUntilVisible(
      deDupTile,
      100.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('De-duplicate interactions'));
    await tester.pump(); // Scanning dialog
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify confirmation dialog title
    expect(find.text('Merge Duplicate Interactions?'), findsOneWidget);

    // Verify detailed dry run changes are rendered
    expect(
        find.textContaining('Location: [None] → "Starbucks"'), findsOneWidget);
    expect(
        find.textContaining('Mark for prayer: false → true'), findsOneWidget);
    expect(find.textContaining('Add participants: Bob'), findsOneWidget);
    expect(find.textContaining('Notes: Appended additional notes'),
        findsOneWidget);
  });
}
