import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/notification_preference.dart';
import '../models/prayer_request.dart';
import '../repositories/notification_preferences_repository.dart';
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

  @visibleForTesting
  ReminderCoordinator.testHarness({
    ReminderService? reminderService,
    NotificationPreferencesRepository? preferencesRepository,
    DBHelper? dbHelper,
  }) : this._(
          reminderService: reminderService,
          preferencesRepository: preferencesRepository,
          dbHelper: dbHelper,
        );

  static final ReminderCoordinator _instance = ReminderCoordinator._();

  static ReminderCoordinator? _testOverride;

  /// Singleton accessor.
  factory ReminderCoordinator() => _testOverride ?? _instance;

  @visibleForTesting
  static void overrideForTest(ReminderCoordinator coordinator) {
    _testOverride = coordinator;
  }

  @visibleForTesting
  static void resetTestOverride() {
    _testOverride = null;
  }

  final ReminderService _reminderService;
  final NotificationPreferencesRepository _preferencesRepository;
  final DBHelper _dbHelper;

  /// Rebuilds reminders for every stored contact.
  Future<void> refreshAllContacts() async {
    final contacts = await _dbHelper.getContacts();
    for (final contact in contacts) {
      await _refreshForContact(contact);
    }
    await scheduleReviewPrompts(contacts: contacts);
  }

  /// Reloads the contact from persistence and rebuilds reminders.
  Future<void> refreshContact(
    String contactId, {
    bool silent = false,
  }) async {
    final contact = await _dbHelper.getContactById(contactId);
    if (contact == null) {
      return;
    }
    await refreshFromSnapshot(contact, silent: silent);
  }

  /// Rebuilds reminders using the provided [contact] snapshot.
  Future<void> refreshFromSnapshot(
    Contact contact, {
    bool silent = false,
  }) async {
    await _refreshForContact(contact);
    if (!silent) {
      await scheduleReviewPrompts();
    }
  }

  /// Cancels every reminder associated with [contactId].
  Future<void> cancelAllForContact(String contactId) async {
    await _reminderService.cancelAllForContact(contactId);
    await scheduleReviewPrompts();
  }

  /// Synchronises reminders tied to an [interaction].
  Future<void> syncInteractionReminder(
    Contact contact,
    Interaction interaction, {
    bool silent = false,
  }) async {
    try {
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
    } finally {
      if (!silent) {
        await scheduleReviewPrompts();
      }
    }
  }

  /// Removes any reminder scheduled for [interaction].
  Future<void> cancelInteractionReminder(
    Interaction interaction, {
    bool silent = false,
  }) async {
    try {
      if (interaction.id == null) {
        return;
      }
      await _reminderService.cancelReminder(
        ReminderChannel.followUp,
        'interaction_${interaction.id}',
      );
    } finally {
      if (!silent) {
        await scheduleReviewPrompts();
      }
    }
  }

  /// Synchronises reminders for a [PrayerRequest].
  Future<void> syncPrayerRequestReminder(
    Contact contact,
    PrayerRequest request, {
    bool silent = false,
  }) async {
    try {
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
    } finally {
      if (!silent) {
        await scheduleReviewPrompts();
      }
    }
  }

  /// Cancels a reminder tied to [request].
  Future<void> cancelPrayerRequestReminder(
    PrayerRequest request, {
    bool silent = false,
  }) async {
    try {
      if (request.id == null) {
        return;
      }
      await _reminderService.cancelReminder(
        ReminderChannel.prayerUpdate,
        'prayer_${request.id}',
      );
    } finally {
      if (!silent) {
        await scheduleReviewPrompts();
      }
    }
  }

  /// Keeps the weekly and monthly review notifications aligned with the
  /// current state of contacts and prayer requests.
  Future<void> scheduleReviewPrompts({List<Contact>? contacts}) async {
    final dataset = contacts ?? await _dbHelper.getContacts();
    await _scheduleWeeklyPrayerReview(dataset);
    await _scheduleMonthlyContactReview(dataset);
  }

  Future<void> _scheduleWeeklyPrayerReview(List<Contact> contacts) async {
    await _reminderService.cancelReminder(
      ReminderChannel.weeklyReview,
      _weeklyReviewKey,
    );

    final pending = <_PrayerReviewItem>[];
    for (final contact in contacts) {
      for (final request in contact.prayerRequests) {
        if (request.status == PrayerRequestStatus.pending) {
          pending.add(_PrayerReviewItem(contact: contact, request: request));
        }
      }
    }

    if (pending.isEmpty) {
      return;
    }

    final preference = await _preferencesRepository.resolve(
      channel: ReminderChannel.weeklyReview,
      contactId: _globalReviewContactId,
    );
    if (!preference.enabled) {
      return;
    }

    final now = DateTime.now();
    var scheduledFor = _nextWeeklyAnchor(now).add(preference.leadTime);
    if (!scheduledFor.isAfter(now)) {
      scheduledFor = now.add(const Duration(hours: 1));
    }

    final summaryPieces = pending.take(2).map((item) {
      final contactName = item.contact.fullName;
      return '${item.request.description} ($contactName)';
    }).toList();

    var body = pending.length == 1
        ? '1 pending prayer request needs an update.'
        : '${pending.length} pending prayer requests need updates.';
    if (summaryPieces.isNotEmpty) {
      body = '$body • ${summaryPieces.join(' • ')}';
    }

    final contactIds = pending.map((item) => item.contact.id).toSet().toList();
    final prayerIds =
        pending.map((item) => item.request.id).whereType<int>().toList();

    await _reminderService.scheduleReminder(
      channel: ReminderChannel.weeklyReview,
      key: _weeklyReviewKey,
      scheduledAt: scheduledFor,
      title: 'Weekly prayer review',
      body: body,
      additionalPayload: {
        'target': 'prayer_requests',
        'count': pending.length,
        'contactIds': contactIds,
        'prayerIds': prayerIds,
      },
    );
  }

  Future<void> _scheduleMonthlyContactReview(List<Contact> contacts) async {
    await _reminderService.cancelReminder(
      ReminderChannel.monthlyReview,
      _monthlyReviewKey,
    );

    final now = DateTime.now();
    final staleContacts =
        contacts.where((contact) => _isContactStale(contact, now)).toList();

    if (staleContacts.isEmpty) {
      return;
    }

    final preference = await _preferencesRepository.resolve(
      channel: ReminderChannel.monthlyReview,
      contactId: _globalReviewContactId,
    );
    if (!preference.enabled) {
      return;
    }

    var scheduledFor = _nextMonthlyAnchor(now).add(preference.leadTime);
    if (!scheduledFor.isAfter(now)) {
      scheduledFor = now.add(const Duration(hours: 1));
    }

    final previewNames =
        staleContacts.take(3).map((contact) => contact.fullName).toList();
    var body = staleContacts.length == 1
        ? '${staleContacts.first.fullName} is due for a check-in.'
        : '${staleContacts.length} people could use a fresh check-in.';
    if (previewNames.isNotEmpty && staleContacts.length > 1) {
      body = '$body • ${previewNames.join(', ')}';
    }

    await _reminderService.scheduleReminder(
      channel: ReminderChannel.monthlyReview,
      key: _monthlyReviewKey,
      scheduledAt: scheduledFor,
      title: 'Monthly relationship review',
      body: body,
      additionalPayload: {
        'target': 'stale_contacts',
        'count': staleContacts.length,
        'contactIds': staleContacts.map((contact) => contact.id).toList(),
      },
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
        await syncInteractionReminder(contact, interaction, silent: true);
      } else {
        await cancelInteractionReminder(interaction, silent: true);
      }
    }
    for (final request in contact.prayerRequests) {
      await syncPrayerRequestReminder(contact, request, silent: true);
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
    final firstDayNextMonth =
        (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
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

class _PrayerReviewItem {
  const _PrayerReviewItem({
    required this.contact,
    required this.request,
  });

  final Contact contact;
  final PrayerRequest request;
}

const String _globalReviewContactId = '__global_review__';
const String _weeklyReviewKey = 'weekly_review';
const String _monthlyReviewKey = 'monthly_review';
const Duration _staleContactThreshold = Duration(days: 45);

bool _isContactStale(Contact contact, DateTime reference) {
  DateTime? latestInteraction;
  for (final interaction in contact.interactions) {
    final occurredAt = interaction.occurredAt;
    if (latestInteraction == null || occurredAt.isAfter(latestInteraction)) {
      latestInteraction = occurredAt;
    }
  }

  if (latestInteraction != null) {
    return reference.difference(latestInteraction) > _staleContactThreshold;
  }

  final createdAt = DateTime.tryParse(contact.id);
  if (createdAt == null) {
    return true;
  }
  return reference.difference(createdAt) > _staleContactThreshold;
}

DateTime _nextWeeklyAnchor(
  DateTime reference, {
  int weekday = DateTime.monday,
  int hour = 9,
  int minute = 0,
}) {
  final startOfDay = DateTime(reference.year, reference.month, reference.day);
  var daysUntil = (weekday - startOfDay.weekday) % 7;
  if (daysUntil == 0) {
    daysUntil = 7;
  }
  final targetDate = startOfDay.add(Duration(days: daysUntil));
  return DateTime(
      targetDate.year, targetDate.month, targetDate.day, hour, minute);
}

DateTime _nextMonthlyAnchor(
  DateTime reference, {
  int hour = 9,
  int minute = 0,
}) {
  final month = reference.month == 12 ? 1 : reference.month + 1;
  final year = reference.month == 12 ? reference.year + 1 : reference.year;
  return DateTime(year, month, 1, hour, minute);
}

final RegExp _fullDatePattern = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})');
final RegExp _monthDayPattern = RegExp(r'^(\d{2})[-/](\d{2})');
final RegExp _textualMonthPattern = RegExp(
    r'^(January|February|March|April|May|June|July|August|September|'
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
