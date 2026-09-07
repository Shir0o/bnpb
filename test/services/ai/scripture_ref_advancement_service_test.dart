import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:bnpb/services/ai/scripture_ref_advancement_service.dart';
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

void main() {
  group('ScriptureRefAdvancementService', () {
    test('returns null for null or empty input without calling LLM', () async {
      final llm = _FakeLlm('{}');
      final service = ScriptureRefAdvancementService(llm);

      expect(await service.advance(null), isNull);
      expect(await service.advance(''), isNull);
      expect(llm.lastPrompt, isNull);
    });

    test('returns a chapter-only ref advanced from LLM output', () async {
      final llm = _FakeLlm('{"book":"Psa","start":117,"end":117}');
      final service = ScriptureRefAdvancementService(llm);
      final ref = await service.advance('Read Psa. 117 with Tim');
      expect(ref, isNotNull);
      expect(ref!.book, 'Psa');
      expect(ref.start, 118);
      expect(ref.end, 118);
      expect(ref.display, 'Psa. 118');
    });

    test('returns a chapter-range ref advanced from LLM output', () async {
      final llm = _FakeLlm('{"book":"Psa","start":115,"end":116}');
      final service = ScriptureRefAdvancementService(llm);
      final ref = await service.advance('Read Psa. 115-116 with Tim');
      expect(ref, isNotNull);
      expect(ref!.book, 'Psa');
      expect(ref.start, 117);
      expect(ref.end, 118);
      expect(ref.display, 'Psa. 117–118');
    });

    test('parses a verse-style ref from JSON', () async {
      final llm = _FakeLlm(
        '{"book":"Gen","start":1,"end":1,"verseStart":1,"verseEnd":1}',
      );
      final service = ScriptureRefAdvancementService(llm);
      final ref = await service.advance('Genesis chapter 1 verse 1');
      expect(ref, isNotNull);
      expect(ref!.verseStart, 2);
      expect(ref.display, 'Gen. 1:2');
    });

    test('extracts JSON embedded in prose', () async {
      final llm = _FakeLlm(
        'Sure! The current passage is {"book":"Psa","start":117,"end":117}',
      );
      final service = ScriptureRefAdvancementService(llm);
      final ref = await service.advance('Psalm 117');
      expect(ref?.display, 'Psa. 118');
    });

    test('returns null when LLM produces no JSON', () async {
      final llm = _FakeLlm("I can't help with that.");
      final service = ScriptureRefAdvancementService(llm);
      expect(await service.advance('Psalm 117'), isNull);
    });

    test('returns null when LLM produces malformed JSON', () async {
      final llm = _FakeLlm('{"book":"Psa","start":"not a number"}');
      final service = ScriptureRefAdvancementService(llm);
      expect(await service.advance('Psalm 117'), isNull);
    });

    test('returns null when LLM produces invalid (start > end) range',
        () async {
      final llm = _FakeLlm('{"book":"Psa","start":10,"end":5}');
      final service = ScriptureRefAdvancementService(llm);
      expect(await service.advance('foo'), isNull);
    });

    test('throws StateError when LLM is not ready', () {
      final service = ScriptureRefAdvancementService(
        _FakeLlm('{}', ready: false),
      );
      expect(
        () => service.advance('Psalm 117'),
        throwsA(isA<StateError>()),
      );
    });

    test('prompt includes the user-supplied note text', () async {
      final llm = _FakeLlm('{"book":"Psa","start":117,"end":117}');
      final service = ScriptureRefAdvancementService(llm);
      await service.advance('Read Psalm 117 with Tim');
      expect(llm.lastPrompt, isNotNull);
      expect(llm.lastPrompt!, contains('Read Psalm 117 with Tim'));
    });
  });
}
