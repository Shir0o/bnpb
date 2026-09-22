import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/notification_preference.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/repositories/notification_preferences_repository.dart';
import 'package:bnpb/services/reminder_coordinator.dart';
import 'package:bnpb/services/reminder_service.dart';

class _FakeReminderService extends ReminderService {
  _FakeReminderService() : super.testHarness();

  final List<String> cancelledKeys = [];
  final List<_ScheduledCall> scheduledCalls = [];

  @override
  Future<void> cancelReminder(ReminderChannel channel, String key) async {
    cancelledKeys.add('${channel.name}:$key');
  }

  @override
  Future<void> scheduleReminder({
    required ReminderChannel channel,
    String? contactId,
    required String key,
    required DateTime scheduledAt,
    required String title,
    required String body,
    Map<String, dynamic>? additionalPayload,
  }) async {
    scheduledCalls.add(
      _ScheduledCall(
        channel: channel,
        contactId: contactId,
        key: key,
        scheduledAt: scheduledAt,
        title: title,
        body: body,
      ),
    );
  }
}

class _ScheduledCall {
  const _ScheduledCall({
    required this.channel,
    this.contactId,
    required this.key,
    required this.scheduledAt,
    required this.title,
    required this.body,
  });

  final ReminderChannel channel;
  final String? contactId;
  final String key;
  final DateTime scheduledAt;
  final String title;
  final String body;
}

class _FakePreferencesRepository extends NotificationPreferencesRepository {
  _FakePreferencesRepository(this.preference)
      : super(dbHelper: _FakeDBHelper());

  final ResolvedNotificationPreference preference;

  @override
  Future<ResolvedNotificationPreference> resolve({
    required ReminderChannel channel,
    required String contactId,
    String? category,
  }) async {
    return preference;
  }
}

class _FakeDBHelper extends DBHelper {
  _FakeDBHelper() : super.testHarness();

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return [];
  }
}

void main() {
  late _FakeReminderService fakeReminderService;
  final testContact = Contact(
    id: 'contact-1',
    firstName: 'Jane',
    lastName: 'Doe',
  );

  setUp(() {
    fakeReminderService = _FakeReminderService();
  });

  group('ReminderCoordinator overdue reminders', () {
    test(
        'syncPrayerRequestReminder does NOT schedule overdue prayer requests into future',
        () async {
      final fakePreferences = _FakePreferencesRepository(
        const ResolvedNotificationPreference(
          enabled: true,
          leadTime: Duration(days: 1),
        ),
      );

      final coordinator = ReminderCoordinator.testHarness(
        reminderService: fakeReminderService,
        preferencesRepository: fakePreferences,
        dbHelper: _FakeDBHelper(),
      );

      // requestedAt was 5 days ago, so requestedAt + 1 day lead time was 4 days ago (in the past)
      final overdueRequest = PrayerRequest(
        id: 101,
        participantIds: ['contact-1'],
        description: 'Past prayer request',
        status: PrayerRequestStatus.pending,
        requestedAt: DateTime.now().subtract(const Duration(days: 5)),
      );

      await coordinator.syncPrayerRequestReminder(
        testContact,
        overdueRequest,
        silent: true,
      );

      expect(fakeReminderService.cancelledKeys,
          contains('prayerUpdate:prayer_101'));
      expect(fakeReminderService.scheduledCalls, isEmpty);
    });

    test(
        'syncPrayerRequestReminder schedules future prayer request reminder normally',
        () async {
      final fakePreferences = _FakePreferencesRepository(
        const ResolvedNotificationPreference(
          enabled: true,
          leadTime: Duration(days: 1),
        ),
      );

      final coordinator = ReminderCoordinator.testHarness(
        reminderService: fakeReminderService,
        preferencesRepository: fakePreferences,
        dbHelper: _FakeDBHelper(),
      );

      // requestedAt is now, lead time is 1 day, so scheduledFor is 1 day in the future
      final futureRequestedAt = DateTime.now();
      final futureRequest = PrayerRequest(
        id: 102,
        participantIds: ['contact-1'],
        description: 'Future prayer request',
        status: PrayerRequestStatus.pending,
        requestedAt: futureRequestedAt,
      );

      await coordinator.syncPrayerRequestReminder(
        testContact,
        futureRequest,
        silent: true,
      );

      expect(fakeReminderService.cancelledKeys,
          contains('prayerUpdate:prayer_102'));
      expect(fakeReminderService.scheduledCalls, hasLength(1));
      final call = fakeReminderService.scheduledCalls.first;
      expect(call.channel, ReminderChannel.prayerUpdate);
      expect(call.key, 'prayer_102');
      expect(call.scheduledAt.isAfter(DateTime.now()), isTrue);
    });

    test(
        'syncInteractionReminder does NOT schedule overdue follow-up into future',
        () async {
      final fakePreferences = _FakePreferencesRepository(
        const ResolvedNotificationPreference(
          enabled: true,
          leadTime: Duration(hours: 1),
        ),
      );

      final coordinator = ReminderCoordinator.testHarness(
        reminderService: fakeReminderService,
        preferencesRepository: fakePreferences,
        dbHelper: _FakeDBHelper(),
      );

      // followUpAt was 2 hours ago
      final pastInteraction = Interaction(
        id: 201,
        occurredAt: DateTime.now().subtract(const Duration(days: 1)),
        summary: 'Past coffee chat',
        medium: 'in_person',
        followUpAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await coordinator.syncInteractionReminder(
        testContact,
        pastInteraction,
        silent: true,
      );

      expect(fakeReminderService.cancelledKeys,
          contains('followUp:interaction_201'));
      expect(fakeReminderService.scheduledCalls, isEmpty);
    });

    test('syncInteractionReminder schedules future follow-up normally',
        () async {
      final fakePreferences = _FakePreferencesRepository(
        const ResolvedNotificationPreference(
          enabled: true,
          leadTime: Duration(hours: 1),
        ),
      );

      final coordinator = ReminderCoordinator.testHarness(
        reminderService: fakeReminderService,
        preferencesRepository: fakePreferences,
        dbHelper: _FakeDBHelper(),
      );

      // followUpAt is tomorrow
      final futureFollowUp = DateTime.now().add(const Duration(days: 1));
      final futureInteraction = Interaction(
        id: 202,
        occurredAt: DateTime.now(),
        summary: 'Future meeting',
        medium: 'in_person',
        followUpAt: futureFollowUp,
      );

      await coordinator.syncInteractionReminder(
        testContact,
        futureInteraction,
        silent: true,
      );

      expect(fakeReminderService.cancelledKeys,
          contains('followUp:interaction_202'));
      expect(fakeReminderService.scheduledCalls, hasLength(1));
      final call = fakeReminderService.scheduledCalls.first;
      expect(call.channel, ReminderChannel.followUp);
      expect(call.key, 'interaction_202');
      expect(call.scheduledAt.isAfter(DateTime.now()), isTrue);
    });
  });
}
