import 'dart:convert';

import 'local_llm_service.dart';

/// Suggests tags for a free-text note (interaction body, prayer request,
/// general contact note) using the on-device LLM.
///
/// Returns a small set of normalized lowercase tags. Output is constrained
/// by prompt + post-processing so a small model can't run away with prose.
class AutoTagService {
  AutoTagService(this._llm);

  final LocalLlmService _llm;

  static const int _maxTags = 6;
  static const int _maxTagLength = 24;

  Future<List<String>> suggestTags(String note) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return const [];
    if (!_llm.isReady) {
      throw StateError('AutoTagService called before LLM was loaded');
    }

    final prompt = _buildPrompt(trimmed);
    final raw = await _llm.generate(
      prompt,
      maxTokens: 96,
      temperature: 0.2,
    );
    return _parse(raw);
  }

  String _buildPrompt(String note) {
    // Few-shot prompt biased toward short, snake-case topical tags. We ask
    // for JSON so parsing stays deterministic across small-model quirks.
    return '''
You extract short topic tags from personal-relationship notes.
Rules:
- Output ONLY a JSON array of 1-$_maxTags lowercase strings, no prose.
- Each tag is 1-3 words, snake_case, under $_maxTagLength chars.
- Prefer topics, life events, relationships, emotions. Skip names.

Note: "Caught up with Sarah, she just got a new job at a hospital and is anxious about moving."
Tags: ["new_job","relocation","anxiety","career"]

Note: "Dad's surgery went well, family is grateful."
Tags: ["health","surgery","family","gratitude"]

Note: "${_escape(note)}"
Tags:''';
  }

  String _escape(String s) => s.replaceAll('"', '\\"').replaceAll('\n', ' ');

  List<String> _parse(String raw) {
    final start = raw.indexOf('[');
    final end = raw.indexOf(']', start + 1);
    if (start < 0 || end < 0) return const [];
    final slice = raw.substring(start, end + 1);
    try {
      final decoded = jsonDecode(slice);
      if (decoded is! List) return const [];
      final out = <String>{};
      for (final item in decoded) {
        if (item is! String) continue;
        final tag = _normalize(item);
        if (tag.isEmpty) continue;
        out.add(tag);
        if (out.length >= _maxTags) break;
      }
      return out.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String _normalize(String raw) {
    final lower = raw.toLowerCase().trim();
    final sanitized = lower
        .replaceAll(RegExp(r'[^a-z0-9_\s-]'), '')
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (sanitized.length > _maxTagLength) {
      return sanitized.substring(0, _maxTagLength);
    }
    return sanitized;
  }
}
