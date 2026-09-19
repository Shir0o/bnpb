import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';

/// Parses Simple Time Tracker CSV export files and extracts candidate interactions.
class TimeTrackerParser {
  /// Parses a Simple Time Tracker CSV content and extracts [CandidateInteraction]s
  /// for records tagged with "Contact".
  ///
  /// [markers] are the comment prefixes that signal a contact name follows
  /// (default `w/` and `with `). When a marker is present, only text after it
  /// is scanned for names. When no marker is present, the whole comment is
  /// scanned but only a strong name signature (full name, first+last, or
  /// nickname) counts.
  static List<CandidateInteraction> parseCsv(
    String csvContent, {
    List<Contact> contacts = const [],
    List<String> markers = const ['w/', 'with '],
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
        markers: markers,
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
          // Default to unselected when comment is empty or no contact is matched,
          // so empty/noise records don't silently import without review.
          selected:
              comment.trim().isNotEmpty && extraction.contactIds.isNotEmpty,
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
    required List<String> markers,
  }) {
    if (comment.isEmpty) {
      return _ExtractionResult(
        summary: activityName,
        contactIds: [],
      );
    }

    // 1. Marker-respected first. If a configured marker is present, only the
    // text after it is scanned for names. A bare first name is acceptable here
    // because the marker signals the user's intent to name a contact.
    final marker = _matchMarker(comment, markers);
    if (marker != null) {
      final prefix = marker.$1?.trim();
      final namesPart = marker.$2.trim();

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

    // 2. No marker present: strict whole-comment scan. Only a strong name
    // signature (full name, first+last, or nickname) counts — a bare first
    // name is treated as ambiguous to avoid false auto-associations.
    final strictMatch = _matchStrongName(comment, contacts);
    if (strictMatch != null) {
      final remainder = comment.substring(strictMatch.$2).trim();
      String summary;
      if (remainder.isNotEmpty) {
        summary = '$activityName - $remainder';
      } else {
        summary = '$activityName - $comment';
      }

      return _ExtractionResult(
        summary: summary,
        contactIds: [strictMatch.$1.id],
      );
    }

    // 3. Fallback: general activity with comment.
    return _ExtractionResult(
      summary: '$activityName - $comment',
      contactIds: [],
    );
  }

  /// Returns the first (leftmost) configured marker occurrence in [comment],
  /// as `(prefix, namesPart)` where [prefix] is the text before the marker and
  /// [namesPart] is the text after it. `null` when no marker is present.
  static (String?, String)? _matchMarker(
    String comment,
    List<String> markers,
  ) {
    (String?, String)? best;
    int? bestIndex;

    for (final marker in markers) {
      final m = marker.trim();
      if (m.isEmpty) continue;

      // A marker ending in a word character needs a trailing boundary so it
      // doesn't match inside a longer word (e.g. "with" must not match
      // "within"). Non-word markers (e.g. "w/") already self-delimit.
      final needsBoundary = RegExp(r'[A-Za-z0-9]$').hasMatch(m);
      final pattern = RegExp(
        RegExp.escape(m) + (needsBoundary ? r'(?=\s|$)' : ''),
        caseSensitive: false,
      );

      final match = pattern.firstMatch(comment);
      if (match == null) continue;

      if (bestIndex == null || match.start < bestIndex) {
        bestIndex = match.start;
        final prefix = comment.substring(0, match.start);
        final namesPart = comment.substring(match.end);
        best = (prefix, namesPart);
      }
    }

    return best;
  }

  /// Scans the whole [comment] for a strong contact signature and returns
  /// `(contact, endIndex)` for the longest match, or `null`.
  static (Contact, int)? _matchStrongName(
    String comment,
    List<Contact> contacts,
  ) {
    (Contact, int)? best;
    int bestLength = 0;

    for (final contact in contacts) {
      final namesToCheck = <String>{
        contact.fullName.trim(),
        '${contact.firstName} ${contact.lastName ?? ''}'.trim(),
        if (contact.nickname != null && contact.nickname!.isNotEmpty)
          contact.nickname!.trim(),
      };

      for (final name in namesToCheck) {
        if (name.isEmpty) continue;

        final regex = RegExp(
          r'\b' + RegExp.escape(name) + r'\b',
          caseSensitive: false,
        );
        final match = regex.firstMatch(comment);
        if (match == null) continue;

        // Prefer the longest name signature (full over first, etc.).
        if (name.length > bestLength) {
          bestLength = name.length;
          best = (contact, match.end);
        }
      }
    }

    return best;
  }

  static List<String> _resolveNames(String namesPart, List<Contact> contacts) {
    final matchedIds = <String>{};
    if (namesPart.trim().isEmpty || contacts.isEmpty) return [];

    // Split on common list delimiters: comma, semicolon, &, +, 'and', 'y'
    final rawTokens = namesPart
        .split(RegExp(r'[,;&+]|\b(?:and|y)\b', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    for (final token in rawTokens) {
      // 1. Try matching full name first
      Contact? bestMatch;
      for (final contact in contacts) {
        final fullName = contact.fullName.trim();
        if (fullName.isNotEmpty) {
          final regex = RegExp(r'\b' + RegExp.escape(fullName) + r'\b',
              caseSensitive: false);
          if (regex.hasMatch(token)) {
            bestMatch = contact;
            break;
          }
        }
      }

      if (bestMatch != null) {
        matchedIds.add(bestMatch.id);
        continue;
      }

      // 2. Try matching first names or nicknames word by word in token
      final words = token.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      for (final word in words) {
        final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
        if (cleanWord.isEmpty) continue;

        for (final contact in contacts) {
          final firstName = contact.firstName.trim();
          final nickname = contact.nickname?.trim();

          final isFirstName = firstName.isNotEmpty &&
              firstName.toLowerCase() == cleanWord.toLowerCase();
          final isNickname = nickname != null &&
              nickname.isNotEmpty &&
              nickname.toLowerCase() == cleanWord.toLowerCase();

          if (isFirstName || isNickname) {
            matchedIds.add(contact.id);
          }
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
