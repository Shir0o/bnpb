import 'package:shared_preferences/shared_preferences.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/contact_stage.dart';
import 'contact_service.dart';

/// A suggested, unconfirmed stage change surfaced on the Review screen.
/// Nothing counts toward the review's movement story until it is confirmed.
class StageSuggestion {
  const StageSuggestion({
    required this.contactId,
    required this.name,
    required this.initials,
    required this.from,
    required this.to,
    required this.path,
    required this.why,
  });

  final String contactId;
  final String name;
  final String initials;
  final String from;
  final String to;
  final String path;
  final String why;

  String get dismissalKey => '$contactId:$to';
}

/// Derives stage-change suggestions from logged activity and persists the
/// confirm / "not yet" decisions.
///
/// Inference is deliberately modest: activity can only justify advancing up to
/// "Regular contact". Group/Church/Laboring are set manually on a contact.
class ContactStageService {
  static const String _dismissedPrefKey = 'review.stageSuggestions.dismissed';

  DBHelper get _dbHelper => DBHelper();

  Future<List<StageSuggestion>> buildSuggestions(
    List<Contact> contacts, {
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        prefs.getStringList(_dismissedPrefKey)?.toSet() ?? <String>{};
    final reference = now ?? DateTime.now();
    final suggestions = <StageSuggestion>[];

    for (final contact in contacts) {
      final resolved = contact.resolvedStage;
      final inferred = defaultStageFor(contact.interactions.length);
      if (inferred.index <= resolved.index) continue;

      final target = ContactStage.values[resolved.index + 1];
      final key = '${contact.id}:${target.label}';
      if (dismissed.contains(key)) continue;

      suggestions.add(
        StageSuggestion(
          contactId: contact.id,
          name: contact.displayName,
          initials: contact.initials,
          from: resolved.label,
          to: target.label,
          path: '${resolved.label} → ${target.label}',
          why: _reason(contact, target, reference),
        ),
      );
    }

    suggestions
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return suggestions;
  }

  String _reason(Contact contact, ContactStage target, DateTime now) {
    final cutoff = now.subtract(const Duration(days: 30));
    final recent =
        contact.interactions.where((i) => i.occurredAt.isAfter(cutoff)).length;
    final total = contact.interactions.length;
    if (target == ContactStage.regularContact && recent >= 2) {
      return '$recent interactions in the last 30 days — enough to call this regular.';
    }
    return '$total interaction${total == 1 ? '' : 's'} logged so far.';
  }

  /// Persists a confirmed stage change: updates the contact's stage and
  /// appends a stage move, then dismisses the suggestion so it won't resurface.
  Future<void> confirmSuggestion(
    String contactId,
    String targetStage, {
    String? movedAt,
  }) async {
    final contact = await _dbHelper.getContactById(contactId);
    if (contact == null) return;
    final from = contact.resolvedStageLabel;
    await _dbHelper.setContactStage(
      contactId: contactId,
      toStage: targetStage,
      fromStage: from,
    );
    await _dismiss(contactId, targetStage);
    ContactService().notifyContactsChanged();
  }

  /// Sets a contact's stage directly (contact detail selector). Records the
  /// change as a stage move so it shows up in the review's movement.
  Future<void> setStage(Contact contact, ContactStage target) async {
    final fresh = await _dbHelper.getContactById(contact.id) ?? contact;
    final from = fresh.resolvedStageLabel;
    if (from == target.label) return;
    await _dbHelper.setContactStage(
      contactId: fresh.id,
      toStage: target.label,
      fromStage: from,
    );
    ContactService().notifyContactsChanged();
  }

  Future<void> dismissSuggestion(String contactId, String targetStage) async {
    await _dismiss(contactId, targetStage);
  }

  Future<void> _dismiss(String contactId, String targetStage) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$contactId:$targetStage';
    final current = prefs.getStringList(_dismissedPrefKey) ?? [];
    if (!current.contains(key)) {
      await prefs.setStringList(_dismissedPrefKey, [...current, key]);
    }
  }
}
