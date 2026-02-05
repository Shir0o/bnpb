import 'dart:math';

import 'package:flutter/foundation.dart';
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

  Future<List<ContactMatch>> search(String query) async {
    return compute(
      _performSearch,
      _SearchRequest(contacts: _contacts, query: query),
    );
  }

  static List<ContactMatch> _performSearch(_SearchRequest request) {
    final query = request.query;
    final contacts = request.contacts;
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return contacts
          .map((contact) => ContactMatch(contact: contact, score: 0))
          .toList();
    }

    final results = <ContactMatch>[];
    for (final contact in contacts) {
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
  Future<List<ContactMatch>> searchMeetingContexts(String query) async {
    return compute(
      _performMeetingContextSearch,
      _SearchRequest(contacts: _contacts, query: query),
    );
  }

  static List<ContactMatch> _performMeetingContextSearch(
      _SearchRequest request) {
    final query = request.query;
    final contacts = request.contacts;
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final matches = <ContactMatch>[];
    final formatter = DateFormat.yMMMd();

    for (final contact in contacts) {
      final segments = <_SearchField>[];

      if ((contact.firstMeetingNotes ?? '').isNotEmpty) {
        segments.add(
          _SearchField(
            label: 'First meeting notes',
            values: [contact.firstMeetingNotes!],
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

  static List<_SearchField> _buildGeneralFields(Contact contact) {
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

  static double _score(String normalizedQuery, String text) {
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

  static String _normalize(String value) {
    final lowercase = value.toLowerCase();
    return lowercase.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static Set<String> _trigrams(String text) {
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

  static String? _snippet(String text, String query) {
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

  /// Returns a list of suggested contacts ranked by recency of interaction, then frequency.
  List<ContactMatch> getSuggestions({int limit = 10}) {
    if (_contacts.isEmpty) {
      return const [];
    }

    final scoredContacts = _contacts.map((contact) {
      DateTime? lastInteraction;
      if (contact.interactions.isNotEmpty) {
        // Interactions are guaranteed to be sorted by occurredAt descending.
        lastInteraction = contact.interactions.first.occurredAt;
      }

      return _SuggestionScore(
        contact: contact,
        lastInteraction: lastInteraction,
        interactionCount: contact.interactions.length,
      );
    }).toList();

    // Sort by:
    // 1. Last interaction date (descending)
    // 2. Interaction count (descending)
    // 3. Name (ascending) - handled effectively by stable sort if needed, or explicit tie breaker
    scoredContacts.sort((a, b) {
      // 1. Recency
      if (a.lastInteraction != null && b.lastInteraction != null) {
        final cmp = b.lastInteraction!.compareTo(a.lastInteraction!);
        if (cmp != 0) return cmp;
      } else if (a.lastInteraction != null) {
        return -1; // a comes first
      } else if (b.lastInteraction != null) {
        return 1; // b comes first
      }

      // 2. Frequency
      final countCmp = b.interactionCount.compareTo(a.interactionCount);
      if (countCmp != 0) return countCmp;

      // 3. Name (tie-breaker)
      return a.contact.fullName.compareTo(b.contact.fullName);
    });

    final formatter = DateFormat.yMMMd();

    return scoredContacts.take(limit).map((s) {
      String? description;
      if (s.lastInteraction != null) {
        description = 'Last met ${formatter.format(s.lastInteraction!)}';
      } else if (s.interactionCount > 0) {
        // Should catch cases where interaction might exist but date is null?
        // Ideally checking interactions.isNotEmpty covers it, but defensively:
        description = '${s.interactionCount} interactions';
      }

      return ContactMatch(
        contact: s.contact,
        score: 1.0, // Suggestions treated as high relevance
        matchDescription: description,
      );
    }).toList();
  }
}

class _SuggestionScore {
  final Contact contact;
  final DateTime? lastInteraction;
  final int interactionCount;

  _SuggestionScore({
    required this.contact,
    this.lastInteraction,
    required this.interactionCount,
  });
}

class _SearchField {
  const _SearchField({required this.label, required this.values});

  final String label;
  final List<String> values;
}

class _SearchRequest {
  final List<Contact> contacts;
  final String query;

  _SearchRequest({required this.contacts, required this.query});
}
