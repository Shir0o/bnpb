import 'package:googleapis/calendar/v3.dart' as gcal;

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import 'reminder_coordinator.dart';

/// Service that imports interactions from external calendar providers.
class CalendarIntegrationService {
  CalendarIntegrationService({DBHelper? dbHelper})
      : _dbHelper = dbHelper ?? DBHelper();

  final DBHelper _dbHelper;

  /// Imports events from Google Calendar for the given [contact].
  ///
  /// The service attempts to match events by attendee email, attendee name,
  /// or occurrences of the contact's name within the event summary. Only events
  /// within the provided [start] and [end] range are considered. Existing
  /// interactions with matching contact, timestamp, and summary are skipped
  /// to avoid duplicates.
  Future<List<Interaction>> importForContact({
    required Contact contact,
    required gcal.CalendarApi calendarApi,
    DateTime? start,
    DateTime? end,
    String calendarId = 'primary',
    bool skipExisting = true,
  }) async {
    final normalizedEmails = contact.contactMethods
        .where((method) => method.type.toLowerCase().contains('email'))
        .map((method) => method.value.toLowerCase())
        .toSet();

    final normalizedNames = <String>{
      contact.fullName.toLowerCase(),
      contact.firstName.toLowerCase(),
      if (contact.lastName != null && contact.lastName!.isNotEmpty)
        contact.lastName!.toLowerCase(),
      if (contact.nickname != null && contact.nickname!.isNotEmpty)
        contact.nickname!.toLowerCase(),
    }..removeWhere((value) => value.isEmpty);

    final events = await calendarApi.events.list(
      calendarId,
      timeMin: start?.toUtc(),
      timeMax: end?.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
    );

    final imported = <Interaction>[];

    for (final event in events.items ?? const []) {
      if (!_matchesContact(event, normalizedEmails, normalizedNames)) {
        continue;
      }

      final startDate = _extractDateTime(event.start);
      if (startDate == null) {
        continue;
      }
      final endDate = _extractDateTime(event.end);
      final duration = endDate?.difference(startDate).inMinutes;
      final sanitizedDuration = duration != null && duration > 0 ? duration : null;

      final summary = (event.summary ?? 'Calendar event').trim().isEmpty
          ? 'Calendar event'
          : (event.summary ?? 'Calendar event').trim();

      if (skipExisting) {
        final exists = await _dbHelper.interactionExists(
          contactId: contact.id,
          occurredAt: startDate,
          summary: summary,
        );
        if (exists) {
          continue;
        }
      }

      final interaction = Interaction(
        contactId: contact.id,
        occurredAt: startDate,
        summary: summary,
        medium: 'calendar_event',
        location: event.location,
        attachments: const [],
        durationMinutes: sanitizedDuration,
        category: _deriveCategory(event),
      );

      final saved = await _dbHelper.insertInteraction(interaction);
      await ReminderCoordinator().syncInteractionReminder(contact, saved);
      imported.add(saved);
    }

    return imported;
  }

  bool _matchesContact(
    gcal.Event event,
    Set<String> emails,
    Set<String> names,
  ) {
    final attendees = event.attendees ?? const [];
    final attendeeEmails = attendees
        .map((attendee) => attendee.email?.toLowerCase())
        .whereType<String>();

    if (emails.isNotEmpty && attendeeEmails.any(emails.contains)) {
      return true;
    }

    final attendeeNames = attendees
        .map((attendee) => attendee.displayName?.toLowerCase())
        .whereType<String>();

    if (names.isNotEmpty && attendeeNames.any(names.contains)) {
      return true;
    }

    final summary = event.summary?.toLowerCase() ?? '';
    if (summary.isNotEmpty && names.any((name) => summary.contains(name))) {
      return true;
    }

    return false;
  }

  DateTime? _extractDateTime(gcal.EventDateTime? dateTime) {
    if (dateTime == null) {
      return null;
    }
    if (dateTime.dateTime != null) {
      return dateTime.dateTime!.toLocal();
    }
    if (dateTime.date != null) {
      final date = dateTime.date!;
      return DateTime(date.year, date.month, date.day);
    }
    return null;
  }

  String? _deriveCategory(gcal.Event event) {
    final organizerName = event.organizer?.displayName?.trim();
    if (organizerName != null && organizerName.isNotEmpty) {
      return organizerName;
    }
    final calendarName = event.creator?.displayName?.trim();
    if (calendarName != null && calendarName.isNotEmpty) {
      return calendarName;
    }
    return 'Calendar';
  }
}
