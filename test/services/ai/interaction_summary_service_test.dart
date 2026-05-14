import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/ai/interaction_summary_service.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LocalLlmService {
  _FakeLlm({this.response = '', this.ready = true});
  String response;
  bool ready;
  String? lastPrompt;
  int? lastMaxTokens;

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
    double temperature = 0.7,
  }) async {
    lastPrompt = prompt;
    lastMaxTokens = maxTokens;
    return response;
  }
}

Interaction _make({
  required String summary,
  String? notes,
  DateTime? occurredAt,
  String medium = 'in_person',
  DateTime? deletedAt,
}) {
  return Interaction(
    summary: summary,
    medium: medium,
    notes: notes,
    occurredAt: occurredAt ?? DateTime(2026, 5, 14),
    deletedAt: deletedAt,
  );
}

void main() {
  group('InteractionSummaryService', () {
    test('returns empty when there are no interactions', () async {
      final llm = _FakeLlm(response: 'should not be called');
      final svc = InteractionSummaryService(llm);
      final result = await svc.summarize(const []);
      expect(result, '');
      expect(llm.lastPrompt, isNull);
    });

    test('returns empty when all interactions are blank', () async {
      final llm = _FakeLlm(response: 'unused');
      final svc = InteractionSummaryService(llm);
      final result = await svc.summarize([
        _make(summary: '', notes: ''),
        _make(summary: '   ', notes: null),
      ]);
      expect(result, '');
      expect(llm.lastPrompt, isNull);
    });

    test('throws StateError when LLM is not ready', () async {
      final llm = _FakeLlm(ready: false);
      final svc = InteractionSummaryService(llm);
      expect(
        () => svc.summarize([_make(summary: 'Hi')]),
        throwsA(isA<StateError>()),
      );
    });

    test('caps prompt at maxInteractions and orders by date desc', () async {
      final llm = _FakeLlm(response: 'A neutral summary.');
      final svc = InteractionSummaryService(llm);
      final items = List.generate(
        20,
        (i) => _make(
          summary: 'Entry $i',
          occurredAt: DateTime(2026, 1, 1).add(Duration(days: i)),
        ),
      );
      await svc.summarize(items);
      final prompt = llm.lastPrompt!;
      // Newest entries (high indices) must appear; oldest must not.
      expect(prompt, contains('Entry 19'));
      expect(prompt, contains('Entry 10'));
      expect(prompt, isNot(contains('Entry 9')));
      // Newest-first ordering: 19 should precede 10 in the prompt.
      expect(prompt.indexOf('Entry 19'), lessThan(prompt.indexOf('Entry 10')));
    });

    test('skips soft-deleted interactions', () async {
      final llm = _FakeLlm(response: 'ok');
      final svc = InteractionSummaryService(llm);
      await svc.summarize([
        _make(summary: 'KEEP'),
        _make(summary: 'GONE', deletedAt: DateTime(2026, 5, 1)),
      ]);
      expect(llm.lastPrompt, contains('KEEP'));
      expect(llm.lastPrompt, isNot(contains('GONE')));
    });

    test('strips a leading "Summary:" label from model output', () async {
      final llm = _FakeLlm(
        response: 'Summary: They had two coffees and a tense call.',
      );
      final svc = InteractionSummaryService(llm);
      final out = await svc.summarize([_make(summary: 'Coffee')]);
      expect(out, 'They had two coffees and a tense call.');
    });

    test('strips code-fence wrapping', () async {
      final llm = _FakeLlm(
        response: '```\nThey have been quiet lately.\n```',
      );
      final svc = InteractionSummaryService(llm);
      final out = await svc.summarize([_make(summary: 'Quiet')]);
      expect(out, 'They have been quiet lately.');
    });

    test('trims to a sentence boundary when output is too long', () async {
      final long = 'They talked. ' * 100; // ~1300 chars
      final llm = _FakeLlm(response: long);
      final svc = InteractionSummaryService(llm);
      final out = await svc.summarize([_make(summary: 'x')]);
      expect(out.length, lessThanOrEqualTo(360));
      expect(out.endsWith('.'), isTrue);
    });

    test('does not include participant ids in the prompt', () async {
      final llm = _FakeLlm(response: 'ok');
      final svc = InteractionSummaryService(llm);
      await svc.summarize([
        Interaction(
          summary: 'Met up',
          medium: 'in_person',
          occurredAt: DateTime(2026, 5, 1),
          participantIds: const ['secret-id-do-not-leak'],
        ),
      ]);
      expect(llm.lastPrompt, isNot(contains('secret-id-do-not-leak')));
    });
  });
}
