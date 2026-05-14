import 'dart:convert';

import '../../models/interaction.dart';
import 'local_llm_service.dart';

class FollowUpSuggestion {
  final String action;
  final int daysFromNow;
  final String? reason;

  const FollowUpSuggestion({
    required this.action,
    required this.daysFromNow,
    this.reason,
  });

  DateTime suggestedDate(DateTime now) =>
      DateTime(now.year, now.month, now.day + daysFromNow, 9, 0);
}

/// Generates a short list of suggested follow-up items based on the
/// just-logged interaction, using the on-device LLM.
///
/// Privacy: only the interaction's own fields (summary, medium, notes) are
/// fed to the model. No other contact information, no history, no PII from
/// other contacts. Output stays on device.
class FollowUpSuggestionService {
  FollowUpSuggestionService(this._llm);

  final LocalLlmService _llm;

  static const int _maxSuggestions = 4;
  static const int _minDays = 1;
  static const int _maxDays = 90;
  static const int _maxActionLength = 80;
  static const int _maxReasonLength = 100;

  Future<List<FollowUpSuggestion>> suggest(Interaction interaction) async {
    final hasContent = interaction.summary.trim().isNotEmpty ||
        (interaction.notes?.trim().isNotEmpty ?? false);
    if (!hasContent) return const [];
    if (!_llm.isReady) {
      throw StateError(
          'FollowUpSuggestionService called before LLM was loaded');
    }

    final prompt = _buildPrompt(interaction);
    final raw = await _llm.generate(
      prompt,
      maxTokens: 256,
      temperature: 0.3,
    );
    return _parse(raw);
  }

  String _buildPrompt(Interaction interaction) {
    final summary = _escape(interaction.summary);
    final medium = _escape(interaction.medium);
    final notes = _escape(interaction.notes ?? '');

    return '''
You suggest concrete follow-up actions after a personal interaction.
Rules:
- Output ONLY a JSON array of 2-$_maxSuggestions objects, no prose.
- Each object has: "action" (short imperative, under $_maxActionLength chars),
  "days" (integer, $_minDays to $_maxDays), "reason" (under $_maxReasonLength chars).
- Actions must be specific and grounded in the note. No generic advice.

Interaction summary: "Coffee with college roommate"
Medium: "in_person"
Notes: "He mentioned interviewing for a senior PM role next Thursday and was nervous."
Output: [
  {"action":"Text him good luck before Thursday's interview","days":6,"reason":"He has a PM interview Thursday"},
  {"action":"Check in on how the interview went","days":10,"reason":"Follow up on outcome"}
]

Interaction summary: "${summary.isEmpty ? "(no summary)" : summary}"
Medium: "$medium"
Notes: "$notes"
Output:''';
  }

  String _escape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' ');

  List<FollowUpSuggestion> _parse(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final slice = raw.substring(start, end + 1);

    final dynamic decoded;
    try {
      decoded = jsonDecode(slice);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];

    final seen = <String>{};
    final out = <FollowUpSuggestion>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final action = _string(item['action']);
      final days = _int(item['days']);
      if (action.isEmpty || days == null) continue;

      final clamped = days.clamp(_minDays, _maxDays);
      final trimmedAction = action.length > _maxActionLength
          ? action.substring(0, _maxActionLength)
          : action;
      final reasonRaw = _string(item['reason']);
      final reason = reasonRaw.isEmpty
          ? null
          : (reasonRaw.length > _maxReasonLength
              ? reasonRaw.substring(0, _maxReasonLength)
              : reasonRaw);

      final dedupKey = trimmedAction.toLowerCase();
      if (!seen.add(dedupKey)) continue;

      out.add(FollowUpSuggestion(
        action: trimmedAction,
        daysFromNow: clamped,
        reason: reason,
      ));
      if (out.length >= _maxSuggestions) break;
    }
    return out;
  }

  String _string(dynamic v) => v is String ? v.trim() : '';

  int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
