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
    expect(coordinator.refreshAllCalled, isTrue);
  });
}

class _SpyReminderCoordinator extends ReminderCoordinator {
  _SpyReminderCoordinator() : super.testHarness();

  bool refreshAllCalled = false;

  @override
  Future<void> refreshAllContacts() async {
    refreshAllCalled = true;
  }
}
