import 'dart:math';

import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/notification_preference.dart';
import '../models/prayer_request.dart';
import 'notification_preferences_repository.dart';
import 'reminder_service.dart';

/// Centralises the logic required to keep reminder notifications in sync with
/// timeline, prayer, and significant date changes.
class ReminderCoordinator {
  ReminderCoordinator._({
    ReminderService? reminderService,
    NotificationPreferencesRepository? preferencesRepository,
    DBHelper? dbHelper,
  })  : _reminderService = reminderService ?? ReminderService(),
        _preferencesRepository =
            preferencesRepository ?? NotificationPreferencesRepository(),
        _dbHelper = dbHelper ?? DBHelper();

  static final ReminderCoordinator _instance =
      ReminderCoordinator._();

  /// Singleton accessor.
  factory ReminderCoordinator() => _instance;

  final ReminderService _reminderService;
  final NotificationPreferencesRepository _preferencesRepository;
  final DBHelper _dbHelper;

  /// Rebuilds reminders for every stored contact.
  Future<void> refreshAllContacts() async {
    final contacts = await _dbHelper.getContacts();
    for (final contact in contacts) {
      await _refreshForContact(contact);
    }
  }

  /// Reloads the contact from persistence and rebuilds reminders.
  Future<void> refreshContact(String contactId) async {
    final contact = await _dbHelper.getContactById(contactId);
    if (contact == null) {
      return;
    }
    await _refreshForContact(contact);
  }

  /// Cancels every reminder associated with [contactId].
  Future<void> cancelAllForContact(String contactId) {
    return _reminderService.cancelAllForContact(contactId);
  }

  /// Synchronises reminders tied to an [interaction].
  Future<void> syncInteractionReminder(
    Contact contact,
    Interaction interaction,
  ) async {
    if (interaction.id == null) {
      return;
    }
    final key = 'interaction_${interaction.id}';
    await _reminderService.cancelReminder(ReminderChannel.followUp, key);

    final followUpAt = interaction.followUpAt;
    if (followUpAt == null) {
      return;
    }

    final preference = await _preferencesRepository.resolve(
      channel: ReminderChannel.followUp,
      contactId: contact.id,
      category: interaction.category,
    );
    if (!preference.enabled) {
      return;
    }

    var scheduledFor = followUpAt.subtract(preference.leadTime);
    if (!scheduledFor.isAfter(DateTime.now())) {
      scheduledFor = DateTime.now().add(const Duration(minutes: 5));
    }

    final formattedFollowUp =
        DateFormat.yMMMd().add_jm().format(followUpAt.toLocal());
    final body =
        'Planned follow-up at $formattedFollowUp • ${interaction.summary}';

    await _reminderService.scheduleReminder(
      channel: ReminderChannel.followUp,
      contactId: contact.id,
      key: key,
      scheduledAt: scheduledFor,
      title: 'Follow up with ${contact.fullName}',
      body: body,
    );
  }

  /// Removes any reminder scheduled for [interaction].
  Future<void> cancelInteractionReminder(Interaction interaction) async {
    if (interaction.id == null) {
      return;
    }
    await _reminderService.cancelReminder(
      ReminderChannel.followUp,
      'interaction_${interaction.id}',
    );
  }

  /// Synchronises reminders for a [PrayerRequest].
  Future<void> syncPrayerRequestReminder(
    Contact contact,
    PrayerRequest request,
  ) async {
    if (request.id == null) {
      return;
    }
    final key = 'prayer_${request.id}';
    await _reminderService.cancelReminder(ReminderChannel.prayerUpdate, key);

    if (request.status != PrayerRequestStatus.pending) {
      return;
    }

    final preference = await _preferencesRepository.resolve(
      channel: ReminderChannel.prayerUpdate,
      contactId: contact.id,
      category: request.category,
    );
    if (!preference.enabled) {
      return;
    }

    var scheduledFor = request.requestedAt.add(preference.leadTime);
    if (!scheduledFor.isAfter(DateTime.now())) {
      scheduledFor = DateTime.now().add(const Duration(hours: 1));
    }

    final body =
        'Check in on "${request.description}" for ${contact.fullName}.';

    await _reminderService.scheduleReminder(
      channel: ReminderChannel.prayerUpdate,
      contactId: contact.id,
      key: key,
      scheduledAt: scheduledFor,
      title: 'Prayer update needed',
      body: body,
    );
  }

  /// Cancels a reminder tied to [request].
  Future<void> cancelPrayerRequestReminder(PrayerRequest request) async {
    if (request.id == null) {
      return;
    }
    await _reminderService.cancelReminder(
      ReminderChannel.prayerUpdate,
      'prayer_${request.id}',
    );
  }

  /// Synchronises significant date reminders for [contact].
  Future<void> syncSignificantDates(Contact contact) async {
    await _reminderService.cancelChannelForContact(
      ReminderChannel.significantDate,
      contact.id,
    );

    final preference = await _preferencesRepository.resolve(
      channel: ReminderChannel.significantDate,
      contactId: contact.id,
    );
    if (!preference.enabled) {
      return;
    }

    final significantDates = _extractSignificantDates(contact);
    for (final date in significantDates) {
      var scheduledFor = date.when.subtract(preference.leadTime);
      if (!scheduledFor.isAfter(DateTime.now())) {
        continue;
      }
      await _reminderService.scheduleReminder(
        channel: ReminderChannel.significantDate,
        contactId: contact.id,
        key: 'significant_${contact.id}_${date.key}',
        scheduledAt: scheduledFor,
        title: 'Upcoming for ${contact.fullName}',
        body: date.label,
      );
    }
  }

  Future<void> _refreshForContact(Contact contact) async {
    await syncSignificantDates(contact);
    for (final interaction in contact.interactions) {
      if (interaction.followUpAt != null) {
        await syncInteractionReminder(contact, interaction);
      } else {
        await cancelInteractionReminder(interaction);
      }
    }
    for (final request in contact.prayerRequests) {
      await syncPrayerRequestReminder(contact, request);
    }
  }

  List<_SignificantDate> _extractSignificantDates(Contact contact) {
    final now = DateTime.now();
    final results = <_SignificantDate>[];
    for (final raw in contact.recognitionReminders) {
      final reminder = raw.trim();
      if (reminder.isEmpty) {
        continue;
      }
      final parsed = _parseReminder(reminder, now);
      if (parsed == null) {
        continue;
      }
      if (!parsed.when.isAfter(now)) {
        continue;
      }
      results.add(parsed);
    }
    return results;
  }

  _SignificantDate? _parseReminder(String reminder, DateTime reference) {
    final normalized = reminder.trim();
    final fullDateMatch = _fullDatePattern.firstMatch(normalized);
    if (fullDateMatch != null) {
      final year = int.tryParse(fullDateMatch.group(1)!);
      final month = int.tryParse(fullDateMatch.group(2)!);
      final day = int.tryParse(fullDateMatch.group(3)!);
      if (year == null || month == null || day == null) {
        return null;
      }
      final when = DateTime(year, month, day, 9);
      return _SignificantDate(
        key: _sanitizeKey(normalized),
        when: when,
        label: normalized,
      );
    }

    final monthDayMatch = _monthDayPattern.firstMatch(normalized);
    if (monthDayMatch != null) {
      final month = int.tryParse(monthDayMatch.group(1)!);
      final day = int.tryParse(monthDayMatch.group(2)!);
      if (month == null || day == null) {
        return null;
      }
      var year = reference.year;
      var when = DateTime(year, month, min(day, _daysInMonth(year, month)), 9);
      if (!when.isAfter(reference)) {
        year += 1;
        when = DateTime(year, month, min(day, _daysInMonth(year, month)), 9);
      }
      return _SignificantDate(
        key: _sanitizeKey(normalized),
        when: when,
        label: normalized,
      );
    }

    final textualMatch = _textualMonthPattern.firstMatch(normalized);
    if (textualMatch != null) {
      final monthName = textualMatch.group(1)!;
      final month = _monthLookup[monthName.toLowerCase()];
      final day = int.tryParse(textualMatch.group(2)!);
      if (month == null || day == null) {
        return null;
      }
      var year = reference.year;
      var when = DateTime(year, month, min(day, _daysInMonth(year, month)), 9);
      if (!when.isAfter(reference)) {
        year += 1;
        when = DateTime(year, month, min(day, _daysInMonth(year, month)), 9);
      }
      return _SignificantDate(
        key: _sanitizeKey(normalized),
        when: when,
        label: normalized,
      );
    }

    return null;
  }

  int _daysInMonth(int year, int month) {
    final firstDayNextMonth = (month == 12)
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return firstDayNextMonth.subtract(const Duration(days: 1)).day;
  }

  String _sanitizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }
}

class _SignificantDate {
  const _SignificantDate({
    required this.key,
    required this.when,
    required this.label,
  });

  final String key;
  final DateTime when;
  final String label;
}

final RegExp _fullDatePattern = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})');
final RegExp _monthDayPattern = RegExp(r'^(\d{2})[-/](\d{2})');
final RegExp _textualMonthPattern =
    RegExp(r'^(January|February|March|April|May|June|July|August|September|'
        r'October|November|December)\s+(\d{1,2})',
        caseSensitive: false);

const Map<String, int> _monthLookup = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};
