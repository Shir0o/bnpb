import 'dart:convert';

import '../../models/interaction.dart';
import 'local_llm_service.dart';

/// Generates a short, neutral, on-device summary of a contact's recent
/// interaction history. Designed to answer "what's going on with this
/// person?" without requiring the user to scan a long list manually.
///
/// Privacy: the prompt only includes the [Interaction]'s own fields
/// (summary, medium, notes, occurredAt). No other contact's name, no
/// participant ids, no extra identifiers. Output stays on device.
class InteractionSummaryService {
  InteractionSummaryService(this._llm);

  final LocalLlmService _llm;

  /// How many of the most-recent interactions to feed to the model.
  /// Anything older is dropped before prompting to keep latency and
  /// token usage bounded on small on-device models.
  static const int maxInteractions = 10;
  static const int _minInteractions = 1;
  static const int _maxSummaryChars = 360;

  /// Produces a 2-3 sentence digest of [interactions]. The list does not
  /// need to be pre-sorted; the service sorts by `occurredAt` descending
  /// and keeps the most recent [maxInteractions]. Returns an empty string
  /// when there is nothing meaningful to summarize.
  Future<String> summarize(List<Interaction> interactions) async {
    if (!_llm.isReady) {
      throw StateError(
          'InteractionSummaryService called before LLM was loaded');
    }
    final recent = _selectRecent(interactions);
    if (recent.length < _minInteractions) return '';

    final raw = await _llm.generate(
      _buildPrompt(recent),
      maxTokens: 192,
      temperature: 0.3,
    );
    return _postProcess(raw);
  }

  List<Interaction> _selectRecent(List<Interaction> interactions) {
    final filtered = interactions
        .where((i) =>
            i.deletedAt == null &&
            (i.summary.trim().isNotEmpty ||
                (i.notes?.trim().isNotEmpty ?? false)))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (filtered.length <= maxInteractions) return filtered;
    return filtered.sublist(0, maxInteractions);
  }

  String _buildPrompt(List<Interaction> recent) {
    final entries = recent.map((i) {
      final notes = (i.notes ?? '').trim();
      return {
        'date': _isoDate(i.occurredAt),
        'medium': i.medium,
        'summary': i.summary.trim(),
        if (notes.isNotEmpty) 'notes': notes,
      };
    }).toList();

    return '''
You write neutral, observational summaries of someone's recent
interactions, in 2-3 plain sentences. No bullet lists, no headings,
no quoted text, no advice. Refer to the person as "they"; do not
invent names. Stay grounded in the entries.

Entries (most recent first):
${jsonEncode(entries)}

Summary:''';
  }

  String _isoDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  String _postProcess(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    // Models sometimes echo the "Summary:" label or wrap the answer in
    // quotes / code fences. Strip those defensively.
    text = text.replaceFirst(RegExp(r'^\s*```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'```\s*$'), '');
    text = text.replaceFirst(
        RegExp(r'^(summary|digest)\s*:\s*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'^["‘’“”]'), '');
    text = text.replaceAll(RegExp(r'["‘’“”]$'), '');

    text = text.trim();
    if (text.length > _maxSummaryChars) {
      // Trim to last sentence break before the cap to avoid awkward cuts.
      final cut = text.substring(0, _maxSummaryChars);
      final lastStop = cut.lastIndexOf(RegExp(r'[.!?]\s'));
      text = lastStop > 0 ? cut.substring(0, lastStop + 1).trim() : cut.trim();
    }
    return text;
  }
}
