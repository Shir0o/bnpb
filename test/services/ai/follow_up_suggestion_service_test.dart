import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/ai/follow_up_suggestion_service.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LocalLlmService {
  _FakeLlm(this._response, {this.ready = true});
  final String _response;
  final bool ready;
  String? lastPrompt;

  @override
  bool get isReady => ready;

  @override
  Future<void> load(String modelPath) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async {
    lastPrompt = prompt;
    return _response;
  }
}

Interaction _interaction({
  String summary = 'Coffee with Sarah',
  String medium = 'in_person',
  String? notes = 'She just got a new job and is anxious about moving.',
}) {
  return Interaction(
    occurredAt: DateTime(2026, 5, 13),
    summary: summary,
    medium: medium,
    notes: notes,
  );
}

void main() {
  group('FollowUpSuggestionService', () {
    test('parses well-formed JSON suggestions', () async {
      final llm = _FakeLlm('''
[
  {"action":"Send a moving checklist","days":3,"reason":"Help with relocation stress"},
  {"action":"Check in after first week at job","days":14,"reason":"Follow up on new role"}
]''');
      final service = FollowUpSuggestionService(llm);
      final suggestions = await service.suggest(_interaction());
      expect(suggestions, hasLength(2));
      expect(suggestions[0].action, 'Send a moving checklist');
      expect(suggestions[0].daysFromNow, 3);
      expect(suggestions[0].reason, 'Help with relocation stress');
      expect(suggestions[1].daysFromNow, 14);
    });

    test('extracts JSON array embedded in prose', () async {
      final llm = _FakeLlm(
        'Sure, here are ideas: [{"action":"Pray for her","days":1}] done.',
      );
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(suggestions, hasLength(1));
      expect(suggestions[0].action, 'Pray for her');
    });

    test('clamps days to the allowed window', () async {
      final llm = _FakeLlm('''
[
  {"action":"Immediate ping","days":0},
  {"action":"Far-future note","days":500}
]''');
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(suggestions[0].daysFromNow, 1);
      expect(suggestions[1].daysFromNow, 90);
    });

    test('coerces stringified day numbers', () async {
      final llm = _FakeLlm('[{"action":"X","days":"7"}]');
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(suggestions.single.daysFromNow, 7);
    });

    test('drops malformed entries but keeps valid ones', () async {
      final llm = _FakeLlm('''
[
  {"action":"Good one","days":5},
  {"days":7},
  {"action":"No days here"},
  "not even an object",
  {"action":"Another good one","days":10}
]''');
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(
          suggestions.map((s) => s.action), ['Good one', 'Another good one']);
    });

    test('deduplicates suggestions with identical actions', () async {
      final llm = _FakeLlm('''
[
  {"action":"Send a card","days":3},
  {"action":"SEND A CARD","days":7},
  {"action":"Send a different thing","days":5}
]''');
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(suggestions, hasLength(2));
      expect(suggestions[0].action, 'Send a card');
      expect(suggestions[1].action, 'Send a different thing');
    });

    test('caps at 4 suggestions', () async {
      final llm = _FakeLlm('''
[
  {"action":"A","days":1},{"action":"B","days":2},
  {"action":"C","days":3},{"action":"D","days":4},
  {"action":"E","days":5},{"action":"F","days":6}
]''');
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(suggestions, hasLength(4));
    });

    test('returns empty list when no JSON array present', () async {
      final llm = _FakeLlm("I can't help with that.");
      final suggestions =
          await FollowUpSuggestionService(llm).suggest(_interaction());
      expect(suggestions, isEmpty);
    });

    test(
        'returns empty list when interaction has no content, without calling LLM',
        () async {
      final llm = _FakeLlm('[{"action":"should not appear","days":3}]');
      final service = FollowUpSuggestionService(llm);
      final empty =
          await service.suggest(_interaction(summary: '', notes: null));
      expect(empty, isEmpty);
      expect(llm.lastPrompt, isNull);
    });

    test('throws StateError when LLM is not ready', () async {
      final service = FollowUpSuggestionService(_FakeLlm('', ready: false));
      expect(
        () => service.suggest(_interaction()),
        throwsA(isA<StateError>()),
      );
    });

    test('suggestedDate adds days at 9am local time', () {
      const s = FollowUpSuggestion(action: 'x', daysFromNow: 3);
      final base = DateTime(2026, 5, 13, 14, 30);
      final out = s.suggestedDate(base);
      expect(out.year, 2026);
      expect(out.month, 5);
      expect(out.day, 16);
      expect(out.hour, 9);
      expect(out.minute, 0);
    });
  });
}
