import 'dart:math';

import 'package:intl/intl.dart';

import '../models/contact.dart';
import '../models/interaction.dart';

/// Represents a scored match for a contact search query.
class ContactMatch {
  ContactMatch({
    required this.contact,
    required this.score,
    this.matchDescription,
    this.snippet,
  });

  final Contact contact;
  final double score;
  final String? matchDescription;
  final String? snippet;
}

/// Provides fuzzy search across contacts, tags, notes, and recognition cues.
class ContactSearchService {
  List<Contact> _contacts = const [];

  void index(List<Contact> contacts) {
    _contacts = List<Contact>.from(contacts);
  }

  List<ContactMatch> search(String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return _contacts
          .map((contact) => ContactMatch(contact: contact, score: 0))
          .toList();
    }

    final results = <ContactMatch>[];
    for (final contact in _contacts) {
      final fields = _buildGeneralFields(contact);
      final combinedText = fields.expand((field) => field.values).join(' ');
      final combinedScore = _score(normalizedQuery, combinedText);

      if (combinedScore <= 0) {
        continue;
      }

      double bestFieldScore = 0;
      String? bestFieldLabel;
      String? bestFieldSnippet;

      for (final field in fields) {
        final fieldText = field.values.join(' ');
        if (fieldText.trim().isEmpty) {
          continue;
        }
        final fieldScore = _score(normalizedQuery, fieldText);
        if (fieldScore > bestFieldScore) {
          bestFieldScore = fieldScore;
          bestFieldLabel = field.label;
          bestFieldSnippet = _snippet(fieldText, query);
        }
      }

      results.add(
        ContactMatch(
          contact: contact,
          score: max(combinedScore, bestFieldScore),
          matchDescription: bestFieldLabel,
          snippet: bestFieldSnippet,
        ),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Specialized lookup for "met at ..." or meeting context style queries.
  List<ContactMatch> searchMeetingContexts(String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final matches = <ContactMatch>[];
    final formatter = DateFormat.yMMMd();

    for (final contact in _contacts) {
      final segments = <_SearchField>[];

      if ((contact.firstMeetingNotes ?? '').isNotEmpty) {
        segments.add(
          _SearchField(
            label: 'First meeting notes',
            values: [contact.firstMeetingNotes!],
          ),
        );
      }

      if ((contact.dietaryPreference ?? '').isNotEmpty) {
        segments.add(
          _SearchField(
            label: 'Dietary preferences',
            values: [contact.dietaryPreference!],
          ),
        );
      }

      for (final Interaction interaction in contact.interactions) {
        final parts = <String>[];
        if ((interaction.location ?? '').isNotEmpty) {
          parts.add(interaction.location!);
        }
        parts.add(interaction.summary);
        segments.add(
          _SearchField(
            label: 'Interaction on ${formatter.format(interaction.occurredAt)}',
            values: parts,
          ),
        );
      }

      double bestScore = 0;
      String? bestLabel;
      String? bestSnippet;

      for (final field in segments) {
        final text = field.values.join(' ');
        if (text.trim().isEmpty) {
          continue;
        }
        final score = _score(normalizedQuery, text);
        if (score > bestScore) {
          bestScore = score;
          bestLabel = field.label;
          bestSnippet = _snippet(text, query);
        }
      }

      if (bestScore > 0) {
        matches.add(
          ContactMatch(
            contact: contact,
            score: bestScore,
            matchDescription: bestLabel,
            snippet: bestSnippet,
          ),
        );
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  List<_SearchField> _buildGeneralFields(Contact contact) {
    final formatter = DateFormat.yMMMd();
    final interactionSummaries = contact.interactions
        .map(
          (Interaction interaction) =>
              '${formatter.format(interaction.occurredAt)} ${interaction.summary} ${interaction.location ?? ''}',
        )
        .toList();

    return [
      _SearchField(
        label: 'Name',
        values: [contact.fullName, contact.nickname ?? ''],
      ),
      _SearchField(
        label: 'Location',
        values: [contact.location ?? ''],
      ),
      _SearchField(
        label: 'Dietary preferences',
        values: [contact.dietaryPreference ?? ''],
      ),
      _SearchField(
        label: 'Tags',
        values: contact.tags,
      ),
      _SearchField(
        label: 'First meeting notes',
        values: [contact.firstMeetingNotes ?? ''],
      ),
      _SearchField(
        label: 'Recognition keywords',
        values: contact.recognitionKeywords,
      ),
      _SearchField(
        label: 'Recognition reminders',
        values: contact.recognitionReminders,
      ),
      _SearchField(
        label: 'Interactions',
        values: interactionSummaries,
      ),
    ];
  }

  double _score(String normalizedQuery, String text) {
    final normalizedText = _normalize(text);
    if (normalizedQuery.isEmpty || normalizedText.isEmpty) {
      return 0;
    }

    if (normalizedText.contains(normalizedQuery)) {
      final ratio = normalizedQuery.length / normalizedText.length;
      return 0.6 + 0.4 * ratio.clamp(0.0, 1.0);
    }

    final queryTrigrams = _trigrams(normalizedQuery);
    final textTrigrams = _trigrams(normalizedText);
    if (queryTrigrams.isEmpty || textTrigrams.isEmpty) {
      return 0;
    }

    final intersection = queryTrigrams.intersection(textTrigrams).length;
    return (2 * intersection) / (queryTrigrams.length + textTrigrams.length);
  }

  String _normalize(String value) {
    final lowercase = value.toLowerCase();
    return lowercase.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  Set<String> _trigrams(String text) {
    if (text.length <= 3) {
      return {text};
    }
    final padded = '  $text  ';
    final grams = <String>{};
    for (var i = 0; i < padded.length - 2; i++) {
      grams.add(padded.substring(i, i + 3));
    }
    return grams;
  }

  String? _snippet(String text, String query) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final lowerText = trimmed.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index == -1) {
      return trimmed.length > 120 ? '${trimmed.substring(0, 117)}…' : trimmed;
    }

    final start = max(0, index - 40);
    final end = min(trimmed.length, index + lowerQuery.length + 40);
    final snippet = trimmed.substring(start, end);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < trimmed.length ? '…' : '';
    return '$prefix$snippet$suffix';
  }
}

class _SearchField {
  const _SearchField({required this.label, required this.values});

  final String label;
  final List<String> values;
}
