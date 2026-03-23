import '../models/contact.dart';
import 'reminder_coordinator.dart';

typedef ContactPersister = Future<void> Function(Contact contact);

/// Persists [contacts] originating from a legacy backup and ensures reminder
/// state is rebuilt for each snapshot.
Future<void> processLegacyContacts({
  required Iterable<Contact> contacts,
  required ContactPersister persistContact,
  ReminderCoordinator? reminderCoordinator,
}) async {
  final coordinator = reminderCoordinator ?? ReminderCoordinator();
  for (final contact in contacts) {
    await persistContact(contact);
  }
  await coordinator.refreshAllContacts();
}
