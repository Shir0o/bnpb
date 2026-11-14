import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/main.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/notification_preference.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/screens/settings_page.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/reminder_service.dart';
import 'package:bnpb/services/security_service.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:bnpb/services/ai/ai_services.dart';

import 'repositories/mock_db_helper.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}

class MockReminderService extends Mock implements ReminderService {}

class MockSecurityService extends Mock implements SecurityService {}

class FakeDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  final List<PrayerRequest> prayerRequests = [];
  final List<Interaction> interactions = [];
  final List<NotificationPreference> preferences = [];
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

  @override
  Future<List<NotificationPreference>> getNotificationPreferences({
    NotificationScopeType? scopeType,
  }) async {
    if (scopeType == null) return preferences;
    return preferences.where((p) => p.scopeType == scopeType).toList();
  }

  @override
  Future<NotificationPreference?> getNotificationPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    for (final preference in preferences) {
      if (preference.scopeType == scopeType &&
          preference.scopeId == scopeId &&
          preference.channel == channel) {
        return preference;
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
    SharedPreferences.setMockInitialValues({
      'onboarding.completed': true,
    });

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

    fakeDbHelper.contacts.addAll([
      Contact(
        id: 'c1',
        firstName: 'Sarah',
        lastName: 'Jenkins',
        location: 'San Francisco',
        updatedAt: DateTime.now(),
      ),
      Contact(
        id: 'c2',
        firstName: 'David',
        lastName: 'Kim',
        location: 'Seattle',
        updatedAt: DateTime.now(),
      ),
    ]);
    fakeDbHelper.counts[PrayerRequestStatus.pending] = 4;
    fakeDbHelper.counts[PrayerRequestStatus.answered] = 12;
    fakeDbHelper.counts[PrayerRequestStatus.archived] = 2;
  });

  tearDown(() {
    ContactService().clearCache();
    AiServices().debugOverride();
    GoogleDriveService.resetTestOverride();
    ReminderService.resetTestOverride();
    SecurityService.resetTestOverride();
    DBHelper.resetTestOverride();
  });

  Widget createTestWidget({
    required Brightness brightness,
    required double textScale,
    required Size size,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light, 13.0),
      darkTheme: buildAppTheme(Brightness.dark, 13.0),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          platformBrightness: brightness,
        ),
        child: const MainPage(),
      ),
    );
  }

  /// Fails with a descriptive reason when any RenderFlex overflow was reported
  /// since the last audit checkpoint, then asserts the accessibility
  /// guidelines on the currently visible screen.
  Future<void> assertUsableState(
    WidgetTester tester, {
    required String name,
    required String state,
    required List<FlutterErrorDetails> errors,
  }) async {
    await tester.pumpAndSettle();

    final overflowErrors = errors
        .where((e) => e.toString().contains('A RenderFlex overflowed'))
        .toList();
    expect(
      overflowErrors,
      isEmpty,
      reason: 'Zero RenderFlex overflows expected in $name / $state',
    );

    await expectLater(
      tester,
      meetsGuideline(androidTapTargetGuideline),
      reason: 'Android tap targets must be at least 48x48 in $name / $state',
    );
    await expectLater(
      tester,
      meetsGuideline(textContrastGuideline),
      reason: 'Text contrast must meet WCAG in $name / $state',
    );
  }

  Future<void> runVariantAudit(
    WidgetTester tester, {
    required String name,
    required Size size,
    required Brightness brightness,
    required double textScale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final List<FlutterErrorDetails> errors = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      errors.add(details);
      originalOnError?.call(details);
    };

    Future<void> checkpoint(String state) {
      return assertUsableState(
        tester,
        name: name,
        state: state,
        errors: errors,
      );
    }

    Finder navIcon(IconData icon) {
      return find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(icon),
      );
    }

    try {
      await tester.pumpWidget(
        createTestWidget(
          brightness: brightness,
          textScale: textScale,
          size: size,
        ),
      );
      await checkpoint('home');

      if (autoUpdateGoldenFiles) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name.png'),
        );
      }

      // Primary navigation click-through.
      await tester.tap(navIcon(Icons.insights_outlined));
      await checkpoint('analytics tab');

      await tester.tap(navIcon(Icons.person_add_outlined));
      await checkpoint('add contact tab');

      await tester.tap(navIcon(Icons.settings_outlined));
      await checkpoint('settings tab');

      // Open a primary dialog from Settings and exercise it.
      final enablePasscode = find.text('Enable passcode');
      final settingsScrollable = find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        enablePasscode,
        200,
        scrollable: settingsScrollable,
      );
      await tester.tap(enablePasscode);
      await checkpoint('set passcode dialog');
      expect(find.text('Set Passcode'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await checkpoint('settings after dialog');
      expect(find.text('Set Passcode'), findsNothing);

      // Back to the initial tab to confirm the shell survives the round trip.
      await tester.tap(navIcon(Icons.home_outlined));
      await checkpoint('back to home');
    } finally {
      FlutterError.onError = originalOnError;
    }
  }

  testWidgets(
    'UI/UX usability audit - phone_light (390x844 @ 1.0x)',
    (WidgetTester tester) async {
      await runVariantAudit(
        tester,
        name: 'phone_light',
        size: const Size(390, 844),
        brightness: Brightness.light,
        textScale: 1.0,
      );
    },
  );

  testWidgets(
    'UI/UX usability audit - phone_dark (390x844 @ 1.0x)',
    (WidgetTester tester) async {
      await runVariantAudit(
        tester,
        name: 'phone_dark',
        size: const Size(390, 844),
        brightness: Brightness.dark,
        textScale: 1.0,
      );
    },
  );

  testWidgets(
    'UI/UX usability audit - small_large_font (320x568 @ 1.6x)',
    (WidgetTester tester) async {
      await runVariantAudit(
        tester,
        name: 'small_large_font',
        size: const Size(320, 568),
        brightness: Brightness.light,
        textScale: 1.6,
      );
    },
  );
}
