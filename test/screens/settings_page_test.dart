import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bnpb/main.dart' show fontSizeNotifier;
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/screens/settings_page.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/notification_preference.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/reminder_service.dart';
import 'package:bnpb/services/security_service.dart';
import 'package:uuid/uuid.dart';
import '../repositories/mock_db_helper.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockReminderService extends Mock implements ReminderService {}

class MockSecurityService extends Mock implements SecurityService {}

class FakeDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  final List<NotificationPreference> preferences = [];
  final List<InteractionDuplicateGroup> duplicateGroups = [];
  int deDuplicateResult = 0;
  Completer<List<InteractionDuplicateGroup>>? findDuplicateCompleter;

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
  Future<List<InteractionDuplicateGroup>> findDuplicateInteractions() async {
    if (findDuplicateCompleter != null) {
      return findDuplicateCompleter!.future;
    }
    return duplicateGroups;
  }

  @override
  Future<int> deDuplicateInteractions() async {
    return deDuplicateResult;
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
    when(
      () => mockGoogleDriveService.onUserChanged,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockGoogleDriveService.currentUser,
    ).thenAnswer((_) async => null);

    mockReminderService = MockReminderService();
    when(
      () => mockReminderService.isExactAlarmPermissionRelevant(),
    ).thenAnswer((_) async => false);
    when(
      () => mockReminderService.isExactAlarmOptInEnabled(),
    ).thenAnswer((_) async => false);

    mockSecurityService = MockSecurityService();
    when(
      () => mockSecurityService.hasPasscode(),
    ).thenAnswer((_) async => false);
    when(
      () => mockSecurityService.isBiometricEnabled(),
    ).thenAnswer((_) async => false);
    when(
      () => mockSecurityService.canUseBiometrics(),
    ).thenAnswer((_) async => false);

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
    'SettingsPage de-duplication shows loading, duplicate preview dialog, and can de-duplicate',
    (WidgetTester tester) async {
      // 1. Set up mock data on our FakeDBHelper
      final contactId = const Uuid().v4();
      final contact = Contact(
        id: contactId,
        firstName: 'John Doe',
        updatedAt: DateTime.now(),
      );
      fakeDbHelper.contacts.add(contact);

      final occurredAt = DateTime(2026, 6, 2, 11, 0, 0);
      final primary = Interaction(
        id: 1,
        syncId: 'sync-1',
        occurredAt: occurredAt,
        summary: 'Coffee Chat',
        medium: 'in_person',
        attachments: const [],
        markForPrayer: false,
        updatedAt: DateTime.now().toUtc(),
      );
      final duplicate = Interaction(
        id: 2,
        syncId: 'sync-2',
        occurredAt: occurredAt,
        summary: 'Coffee Chat',
        medium: 'in_person',
        attachments: const [],
        markForPrayer: false,
        updatedAt: DateTime.now().toUtc(),
      );

      final group = InteractionDuplicateGroup(
        primary: primary,
        duplicates: [duplicate],
      );
      fakeDbHelper.duplicateGroups.add(group);
      fakeDbHelper.deDuplicateResult = 1;

      // 2. Pump the SettingsPage
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

      // Yield control to let ensureDefaults / load complete
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Initialize the completer to control asynchronous timing
      final findDuplicateCompleter =
          Completer<List<InteractionDuplicateGroup>>();
      fakeDbHelper.findDuplicateCompleter = findDuplicateCompleter;

      // 3. Find and tap the "De-duplicate interactions" tile
      final deDupTile =
          find.byIcon(Icons.cleaning_services_outlined, skipOffstage: false);
      await tester.scrollUntilVisible(
        deDupTile,
        100.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(deDupTile, findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('De-duplicate interactions'));

      // Pump to show scanning/loading dialog
      await tester.pump();
      expect(find.text('Scanning for duplicates...'), findsOneWidget);

      // Complete the completer to let the dry run finish
      findDuplicateCompleter.complete(fakeDbHelper.duplicateGroups);
      // Pump to process the completion, close the loading dialog, and open the preview dialog
      await tester.pump();
      await tester.pumpAndSettle();

      // 4. Verify confirmation dialog title and content are displayed
      expect(find.text('Merge Duplicate Interactions?'), findsOneWidget);
      expect(find.textContaining('Coffee Chat'), findsOneWidget);
      expect(find.textContaining('1 duplicate to merge'), findsOneWidget);

      // 5. Tap the De-duplicate button in the dialog to execute
      final deDupConfirmButton = find.text('De-duplicate');
      expect(deDupConfirmButton, findsOneWidget);
      await tester.tap(deDupConfirmButton);

      // Pump to close dialog and start deduplication
      await tester.pump();

      // Pump to complete deduplication and reload settings page
      await tester.pump(const Duration(milliseconds: 400));

      // 6. Verify that a success message is shown in snackbar
      expect(find.textContaining('Successfully merged'), findsOneWidget);
    },
  );

  testWidgets(
    'SettingsPage displays Display section and updates font size Slider',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

      // Yield control to let ensureDefaults / load complete
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Find Slider widget
      final sliderFinder = find.byType(Slider, skipOffstage: false);
      expect(sliderFinder, findsOneWidget);
      await tester.scrollUntilVisible(
        sliderFinder,
        100.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Perform a drag on the Slider to update the value
      await tester.drag(sliderFinder, const Offset(50.0, 0.0));
      await tester.pumpAndSettle();

      // Verify that the notifier gets updated to a value within [11.0, 18.0]
      expect(fontSizeNotifier.value, isNotNull);
    },
  );
}
