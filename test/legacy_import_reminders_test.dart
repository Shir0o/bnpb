import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/legacy_import_service.dart';
import 'package:bnpb/services/reminder_coordinator.dart';

void main() {
  test('legacy import schedules follow-up reminders once', () async {
    final followUpTime = DateTime.parse('2024-03-15T14:30:00.000Z');
    final contact = Contact(
      id: 'contact-legacy',
      firstName: 'Ada',
      interactions: [
        Interaction(
          id: 42,
          occurredAt: DateTime.parse('2024-03-10T12:00:00.000Z'),
          summary: 'Coffee catch-up',
          medium: 'in_person',
          followUpAt: followUpTime,
        ),
      ],
    );

    final persisted = <Contact>[];
    final coordinator = _SpyReminderCoordinator();

    await processLegacyContacts(
      contacts: [contact],
      persistContact: (value) async {
        persisted.add(value);
      },
      reminderCoordinator: coordinator,
    );

    expect(persisted, [contact]);
    expect(coordinator.followUpScheduledFor, [contact.id]);
    expect(coordinator.followUpSilentFlags, everyElement(isTrue));
    expect(coordinator.reviewPromptCalls, 1);
  });
}

class _SpyReminderCoordinator extends ReminderCoordinator {
  _SpyReminderCoordinator() : super.testHarness();

  final List<String> followUpScheduledFor = [];
  final List<bool> followUpSilentFlags = [];
  int reviewPromptCalls = 0;

  @override
  Future<void> syncSignificantDates(Contact contact) async {}

  @override
  Future<void> syncInteractionReminder(
    Contact contact,
    Interaction interaction, {
    bool silent = false,
  }) async {
    if (interaction.followUpAt != null) {
      followUpScheduledFor.add(contact.id);
      followUpSilentFlags.add(silent);
    }
  }

  @override
  Future<void> cancelInteractionReminder(
    Interaction interaction, {
    bool silent = false,
  }) async {}

  @override
  Future<void> syncPrayerRequestReminder(
    Contact contact,
    PrayerRequest request, {
    bool silent = false,
  }) async {}

  @override
  Future<void> cancelPrayerRequestReminder(
    PrayerRequest request, {
    bool silent = false,
  }) async {}

  @override
  Future<void> scheduleReviewPrompts({List<Contact>? contacts}) async {
    reviewPromptCalls += 1;
  }
}
