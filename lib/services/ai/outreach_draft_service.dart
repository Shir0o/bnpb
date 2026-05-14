import 'dart:convert';

import '../../models/interaction.dart';
import '../../models/prayer_request.dart';
import 'local_llm_service.dart';

/// Short conversation hooks suggested to the user before reaching out
/// to a contact. Each hook is a one-line opener grounded in recent
/// interactions and (optionally) active prayer requests.
///
/// Privacy: this service intentionally takes a wider input slice than
/// [FollowUpSuggestionService] — multiple interactions plus active
/// prayer descriptions — so the privacy documentation calls it out
/// separately. No other-contact names or participant ids are forwarded
/// to the model; only the focal contact's own entries.
class OutreachDraftService {
  OutreachDraftService(this._llm);

  final LocalLlmService _llm;

  static const int maxInteractions = 5;
  static const int maxPrayerRequests = 5;
  static const int _maxHooks = 4;
  static const int _maxHookLength = 120;

  Future<List<String>> suggestHooks({
    required List<Interaction> recentInteractions,
    List<PrayerRequest> activePrayerRequests = const [],
  }) async {
    if (!_llm.isReady) {
      throw StateError('OutreachDraftService called before LLM was loaded');
    }
    final interactions = _selectInteractions(recentInteractions);
    final prayers = _selectPrayers(activePrayerRequests);
    if (interactions.isEmpty && prayers.isEmpty) return const [];

    final raw = await _llm.generate(
      _buildPrompt(interactions: interactions, prayers: prayers),
      maxTokens: 256,
      temperature: 0.4,
    );
    return _parse(raw);
  }

  List<Interaction> _selectInteractions(List<Interaction> all) {
    final filtered = all
        .where((i) =>
            i.deletedAt == null &&
            (i.summary.trim().isNotEmpty ||
                (i.notes?.trim().isNotEmpty ?? false)))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (filtered.length <= maxInteractions) return filtered;
    return filtered.sublist(0, maxInteractions);
  }

  List<PrayerRequest> _selectPrayers(List<PrayerRequest> all) {
    final filtered = all
        .where((p) =>
            p.deletedAt == null &&
            p.status == PrayerRequestStatus.pending &&
            p.description.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    if (filtered.length <= maxPrayerRequests) return filtered;
    return filtered.sublist(0, maxPrayerRequests);
  }

  String _buildPrompt({
    required List<Interaction> interactions,
    required List<PrayerRequest> prayers,
  }) {
    final interactionEntries = interactions
        .map((i) => {
              'date': _isoDate(i.occurredAt),
              'summary': i.summary.trim(),
              if ((i.notes ?? '').trim().isNotEmpty) 'notes': i.notes!.trim(),
            })
        .toList();
    final prayerEntries = prayers
        .map((p) => {
              'requested': _isoDate(p.requestedAt),
              'description': p.description.trim(),
            })
        .toList();

    return '''
You suggest short, specific conversation openers for the user to use
when reaching out to a contact. Refer to the contact as "they" — do
not invent a name. Stay grounded in the entries below; do not invent
events. Each opener is one short sentence the user could actually say.

Rules:
- Output ONLY a JSON array of 2-$_maxHooks strings, no prose.
- Each string is under $_maxHookLength chars.
- No greetings ("Hi", "Hey"), no signoffs — just the hook itself.
- No emoji.

Recent interactions (most recent first):
${jsonEncode(interactionEntries)}

Active prayer requests:
${jsonEncode(prayerEntries)}

Output:''';
  }

  String _isoDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  List<String> _parse(String raw) {
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
    final out = <String>[];
    for (final item in decoded) {
      if (item is! String) continue;
      var hook = item.trim();
      if (hook.isEmpty) continue;
      // Strip leading list markers some models like to add.
      hook = hook.replaceFirst(RegExp(r'^[-*•]\s*'), '');
      if (hook.length > _maxHookLength) {
        hook = hook.substring(0, _maxHookLength).trim();
      }
      final key = hook.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(hook);
      if (out.length >= _maxHooks) break;
    }
    return out;
  }
}
