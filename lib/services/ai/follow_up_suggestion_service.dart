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
/// just-logged interaction, using either the on-device LLM or smart heuristics.
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

  Future<List<FollowUpSuggestion>> suggest(Interaction interaction,
      {DateTime? now}) async {
    final hasContent = interaction.summary.trim().isNotEmpty ||
        (interaction.notes?.trim().isNotEmpty ?? false);
    if (!hasContent) return const [];

    final currentNow = now ?? DateTime.now();

    // Route to heuristic suggestions if total content length is less than 15 characters
    final totalLength = interaction.summary.trim().length +
        (interaction.notes?.trim().length ?? 0);
    if (totalLength < 15) {
      return suggestHeuristic(interaction, currentNow);
    }

    if (!_llm.isReady) {
      throw StateError(
        'FollowUpSuggestionService called before LLM was loaded',
      );
    }

    final prompt = _buildPrompt(interaction, currentNow);
    final raw = await _llm.generate(prompt, maxTokens: 256, temperature: 0.3);
    return _parse(raw);
  }

  /// Generates rule-based smart follow-up suggestions locally without using the LLM.
  List<FollowUpSuggestion> suggestHeuristic(
      Interaction interaction, DateTime now) {
    final summaryLower = interaction.summary.toLowerCase();
    final notesLower = (interaction.notes ?? '').toLowerCase();
    final text = '$summaryLower $notesLower';

    final suggestions = <FollowUpSuggestion>[];

    // Health
    if (text.contains('sick') ||
        text.contains('doctor') ||
        text.contains('health') ||
        text.contains('hospital') ||
        text.contains('surgery') ||
        text.contains('recovery') ||
        text.contains('illness') ||
        text.contains('treatment') ||
        text.contains('hurt') ||
        text.contains('pain') ||
        text.contains('medical')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Ask how they are feeling / recovery update',
        daysFromNow: 3,
        reason: 'Mentioned health/medical issue',
      ));
    }

    // Job
    if (text.contains('job') ||
        text.contains('interview') ||
        text.contains('work') ||
        text.contains('career') ||
        text.contains('promotion') ||
        text.contains('interviewing') ||
        text.contains('resume')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Check in on their job/interview status',
        daysFromNow: 7,
        reason: 'Mentioned job or career updates',
      ));
    }

    // Relocation
    if (text.contains('move') ||
        text.contains('moving') ||
        text.contains('relocate') ||
        text.contains('house') ||
        text.contains('apartment') ||
        text.contains('packing') ||
        text.contains('new home')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Check in on their move and relocation',
        daysFromNow: 14,
        reason: 'Mentioned moving / new home',
      ));
    }

    // Birthday
    if (text.contains('birthday') ||
        text.contains('bday') ||
        text.contains('anniversary') ||
        text.contains('celebrate') ||
        text.contains('celebration')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Send congratulatory note / birthday wishes',
        daysFromNow: 1,
        reason: 'Mentioned birthday/celebration',
      ));
    }

    // Travel
    if (text.contains('travel') ||
        text.contains('trip') ||
        text.contains('vacation') ||
        text.contains('flight') ||
        text.contains('holiday')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Ask how their trip/vacation went',
        daysFromNow: 7,
        reason: 'Mentioned upcoming travel',
      ));
    }

    // Prayer
    if (text.contains('pray') ||
        text.contains('prayer') ||
        text.contains('praying') ||
        text.contains('spiritual') ||
        text.contains('church')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Check in on their prayer request status',
        daysFromNow: 7,
        reason: 'Mentioned prayer/spiritual request',
      ));
    }

    // Family
    if (text.contains('family') ||
        text.contains('kid') ||
        text.contains('child') ||
        text.contains('wife') ||
        text.contains('husband') ||
        text.contains('marriage') ||
        text.contains('wedding') ||
        text.contains('baby') ||
        text.contains('son') ||
        text.contains('daughter')) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Check in on how the family is doing',
        daysFromNow: 14,
        reason: 'Mentioned family/personal life',
      ));
    }

    // Medium-specific suggestions if there is room
    final medium = interaction.medium.toLowerCase();
    if (suggestions.length < 3) {
      if (medium == 'call' || medium == 'phone' || medium == 'video_call') {
        suggestions.add(const FollowUpSuggestion(
          action: 'Schedule another call to catch up',
          daysFromNow: 7,
          reason: 'Stay in touch after phone call',
        ));
        suggestions.add(const FollowUpSuggestion(
          action: 'Send a follow-up text summarizing your call',
          daysFromNow: 1,
          reason: 'Keep lines of communication open',
        ));
      } else if (medium == 'in_person' ||
          medium == 'coffee' ||
          medium == 'lunch' ||
          medium == 'dinner') {
        suggestions.add(const FollowUpSuggestion(
          action: 'Plan another meetup / coffee',
          daysFromNow: 14,
          reason: 'Maintain regular in-person connection',
        ));
        suggestions.add(const FollowUpSuggestion(
          action: 'Send a quick thank you text for the meetup',
          daysFromNow: 1,
          reason: 'Polite follow-up',
        ));
      }
    }

    // General fallbacks if suggestions are still fewer than 2
    if (suggestions.length < 2) {
      suggestions.add(const FollowUpSuggestion(
        action: 'Send a quick check-in message',
        daysFromNow: 7,
        reason: 'Regular touchpoint',
      ));
      suggestions.add(const FollowUpSuggestion(
        action: 'Reach out to say hello',
        daysFromNow: 3,
        reason: 'Casual check-in',
      ));
    }

    // Ensure suggestions are unique and capped
    final seen = <String>{};
    final unique = <FollowUpSuggestion>[];
    for (final s in suggestions) {
      if (seen.add(s.action.toLowerCase())) {
        unique.add(s);
      }
      if (unique.length >= _maxSuggestions) break;
    }
    return unique;
  }

  String _buildPrompt(Interaction interaction, DateTime now) {
    final summary = _escape(interaction.summary);
    final medium = _escape(interaction.medium);
    final notes = _escape(interaction.notes ?? '');

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    String formatDate(DateTime dt) =>
        "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    String formatDateWithWeekday(DateTime dt) =>
        "${formatDate(dt)} (${weekdays[dt.weekday - 1]})";

    final currentStr = formatDateWithWeekday(now);
    final occurredStr = formatDateWithWeekday(interaction.occurredAt);

    return '''
You suggest concrete follow-up actions after a personal interaction.
Rules:
- Output ONLY a JSON array of 2-$_maxSuggestions objects, no prose.
- Each object has: "action" (short imperative, under $_maxActionLength chars),
  "days" (integer, $_minDays to $_maxDays), "reason" (under $_maxReasonLength chars).
- Actions must be specific and grounded in the note. No generic advice.
- Calculate the "days" field to schedule the action relative to the current date (today).
  Use the interaction date to ground relative statements (e.g. "next Thursday" or "tomorrow" in notes)
  and determine the exact difference in days from the current date (today).

Current date: 2026-06-11 (Thursday)
Interaction date: 2026-06-08 (Monday)
Interaction summary: "Coffee with college roommate"
Medium: "in_person"
Notes: "He mentioned interviewing for a senior PM role next Thursday and was nervous."
Explanation: "next Thursday" is Thursday, June 18, 2026. Relative to the current date (June 11, 2026), that is 7 days from now.
Output: [
  {"action":"Text him good luck before Thursday's interview","days":7,"reason":"He has a PM interview Thursday"},
  {"action":"Check in on how the interview went","days":11,"reason":"Follow up on outcome"}
]

Current date: $currentStr
Interaction date: $occurredStr
Interaction summary: ${summary == '""' ? '"(no summary)"' : summary}
Medium: $medium
Notes: $notes
Output:''';
  }

  // jsonEncode quotes the string and escapes embedded control characters,
  // safer than hand-rolled replacement against prompt-injection-style input.
  String _escape(String s) => jsonEncode(s);

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

      out.add(
        FollowUpSuggestion(
          action: trimmedAction,
          daysFromNow: clamped,
          reason: reason,
        ),
      );
      if (out.length >= _maxSuggestions) break;
    }
    return out;
  }

  String _string(dynamic v) => v is String ? v.trim() : '';

  int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return num.tryParse(v.trim())?.round();
    return null;
  }
}
