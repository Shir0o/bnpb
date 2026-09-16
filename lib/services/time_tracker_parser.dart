import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';

/// Parses Simple Time Tracker CSV export files and extracts candidate interactions.
class TimeTrackerParser {
  /// Parses a Simple Time Tracker CSV content and extracts [CandidateInteraction]s
  /// for records tagged with "Contact".
  static List<CandidateInteraction> parseCsv(
    String csvContent, {
    List<Contact> contacts = const [],
  }) {
    if (csvContent.trim().isEmpty) return [];

    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvContent);

    if (rows.isEmpty) return [];

    // Find header column indices
    final headerRow =
        rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    final activityIdx = headerRow.indexOf('activity name');
    final startIdx = headerRow.indexOf('time started');
    final commentIdx = headerRow.indexOf('comment');
    final tagsIdx = headerRow.indexOf('record tags');
    final durationMinIdx = headerRow.indexOf('duration minutes');

    if (activityIdx == -1 || startIdx == -1 || tagsIdx == -1) {
      return [];
    }

    final candidates = <CandidateInteraction>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= tagsIdx) continue;

      final tags = row[tagsIdx].toString();
      if (!tags.toLowerCase().contains('contact')) {
        continue;
      }

      final activityName = row[activityIdx].toString().trim();
      final timeStartedStr = row[startIdx].toString().trim();
      final comment = commentIdx != -1 && row.length > commentIdx
          ? row[commentIdx].toString().trim()
          : '';
      final durationStr = durationMinIdx != -1 && row.length > durationMinIdx
          ? row[durationMinIdx].toString().trim()
          : null;

      DateTime occurredAt;
      try {
        occurredAt = DateTime.parse(timeStartedStr);
      } catch (_) {
        continue;
      }

      final durationMinutes =
          durationStr != null ? int.tryParse(durationStr) : null;

      final fingerprint = _generateFingerprint(
        timeStartedStr: timeStartedStr,
        durationMinutes: durationMinutes,
        activityName: activityName,
        comment: comment,
      );

      final extraction = _extractContactsAndSummary(
        activityName: activityName,
        comment: comment,
        contacts: contacts,
      );

      candidates.add(
        CandidateInteraction(
          fingerprint: fingerprint,
          occurredAt: occurredAt,
          durationMinutes: durationMinutes,
          activityName: activityName,
          summary: extraction.summary,
          matchedContactIds: extraction.contactIds,
          rawComment: comment,
        ),
      );
    }

    return candidates;
  }

  static String _generateFingerprint({
    required String timeStartedStr,
    required int? durationMinutes,
    required String activityName,
    required String comment,
  }) {
    final raw =
        '$timeStartedStr|${durationMinutes ?? ''}|$activityName|$comment';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static _ExtractionResult _extractContactsAndSummary({
    required String activityName,
    required String comment,
    required List<Contact> contacts,
  }) {
    if (comment.isEmpty) {
      return _ExtractionResult(
        summary: activityName,
        contactIds: [],
      );
    }

    // 1. Check for "w/" or "with " pattern
    // e.g. "w/ Abel", "Boba w/ Benji Jeremy Timothy Isai ", "w/ Luis and Mayra "
    final withRegex =
        RegExp(r'(?:^(.*)\s+)?(?:w\/|with\s+)(.*)$', caseSensitive: false);
    final match = withRegex.firstMatch(comment);

    if (match != null) {
      final prefix = match.group(1)?.trim(); // e.g. "Boba" or null
      final namesPart =
          match.group(2)?.trim() ?? ''; // e.g. "Benji Jeremy Timothy Isai"

      final matchedIds = _resolveNames(namesPart, contacts);
      String summary;
      if (prefix != null && prefix.isNotEmpty) {
        summary = '$activityName - $prefix';
      } else {
        summary = '$activityName $comment';
      }

      return _ExtractionResult(
        summary: summary,
        contactIds: matchedIds,
      );
    }

    // 2. Check if comment starts with or matches a contact name
    // e.g. "Edgar Flores ", "Matthew V piano"
    Contact? bestMatch;
    int matchLength = 0;

    for (final contact in contacts) {
      final namesToCheck = [
        contact.fullName.trim(),
        '${contact.firstName} ${contact.lastName ?? ''}'.trim(),
        contact.firstName.trim(),
        if (contact.nickname != null && contact.nickname!.isNotEmpty)
          contact.nickname!.trim(),
      ];

      for (final name in namesToCheck) {
        if (name.isEmpty) continue;
        if (comment.toLowerCase().startsWith(name.toLowerCase())) {
          if (name.length > matchLength) {
            matchLength = name.length;
            bestMatch = contact;
          }
        }
      }
    }

    if (bestMatch != null) {
      final remainder = comment.substring(matchLength).trim();
      String summary;
      if (remainder.isNotEmpty) {
        summary = '$activityName - $remainder';
      } else {
        summary = '$activityName - $comment';
      }

      return _ExtractionResult(
        summary: summary,
        contactIds: [bestMatch.id],
      );
    }

    // 3. Fallback: general activity with comment
    return _ExtractionResult(
      summary: '$activityName - $comment',
      contactIds: [],
    );
  }

  static List<String> _resolveNames(String namesPart, List<Contact> contacts) {
    final matchedIds = <String>{};
    if (namesPart.isEmpty || contacts.isEmpty) return [];

    // Check full name, first name, and nicknames
    for (final contact in contacts) {
      final firstName = contact.firstName.trim().toLowerCase();
      final fullName = contact.fullName.trim().toLowerCase();
      final nickname = contact.nickname?.trim().toLowerCase();

      final regexFirst = RegExp(r'\b' + RegExp.escape(firstName) + r'\b',
          caseSensitive: false);
      if (regexFirst.hasMatch(namesPart)) {
        matchedIds.add(contact.id);
        continue;
      }

      if (fullName.isNotEmpty) {
        final regexFull = RegExp(r'\b' + RegExp.escape(fullName) + r'\b',
            caseSensitive: false);
        if (regexFull.hasMatch(namesPart)) {
          matchedIds.add(contact.id);
          continue;
        }
      }

      if (nickname != null && nickname.isNotEmpty) {
        final regexNick = RegExp(r'\b' + RegExp.escape(nickname) + r'\b',
            caseSensitive: false);
        if (regexNick.hasMatch(namesPart)) {
          matchedIds.add(contact.id);
          continue;
        }
      }
    }

    return matchedIds.toList();
  }
}

class _ExtractionResult {
  final String summary;
  final List<String> contactIds;

  _ExtractionResult({
    required this.summary,
    required this.contactIds,
  });
}
