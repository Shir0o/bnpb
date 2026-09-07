import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:bnpb/services/ai/scripture_ref_advancement_service.dart';
import 'package:bnpb/services/ai/scripture_ref_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LocalLlmService {
  _FakeLlm(this._response, {this.delay = Duration.zero});
  final String _response;
  final Duration delay;
  int callCount = 0;

  @override
  bool get isReady => true;

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
    callCount++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return _response;
  }
}

void main() {
  group('ScriptureRefAdvancementPipeline', () {
    test('returns null for null/empty input without consulting LLM', () async {
      final llm = _FakeLlm('{}');
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
      );

      expect(await pipeline.advance(null, useAi: true), isNull);
      expect(await pipeline.advance('', useAi: true), isNull);
      expect(llm.callCount, 0);
    });

    test('returns regex result without calling LLM', () async {
      final llm = _FakeLlm('{}');
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
      );

      final ref = await pipeline.advance('PSA 115-116', useAi: true);
      expect(ref?.display, 'Psa. 117–118');
      expect(llm.callCount, 0);
    });

    test('falls back to LLM when regex misses', () async {
      final llm = _FakeLlm('{"book":"Psa","start":117,"end":117}');
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
      );

      final ref = await pipeline.advance('Psalm one-seventeen', useAi: true);
      expect(ref?.display, 'Psa. 118');
      expect(llm.callCount, 1);
    });

    test('does not call LLM when useAi is false', () async {
      final llm = _FakeLlm('{}');
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
      );

      final ref = await pipeline.advance('Psalm one-seventeen', useAi: false);
      expect(ref, isNull);
      expect(llm.callCount, 0);
    });

    test('returns null and counts timeout when LLM exceeds latency cap',
        () async {
      final llm = _FakeLlm('{}', delay: const Duration(milliseconds: 500));
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
      );

      final ref = await pipeline.advance('Psalm one-seventeen', useAi: true);
      expect(ref, isNull);
      expect(llm.callCount, 1);
      expect(pipeline.latencyTimeouts, 1);
    });

    test('respects custom latency cap', () async {
      final llm = _FakeLlm('{}', delay: const Duration(milliseconds: 100));
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
        latencyCap: const Duration(milliseconds: 50),
      );

      final ref = await pipeline.advance('Psalm one-seventeen', useAi: true);
      expect(ref, isNull);
      expect(pipeline.latencyTimeouts, 1);
    });

    test('latencyTimeouts accumulates across calls', () async {
      final llm = _FakeLlm('{}', delay: const Duration(milliseconds: 500));
      final pipeline = ScriptureRefAdvancementPipeline(
        ScriptureRefAdvancementService(llm),
      );

      await pipeline.advance('Psalm one', useAi: true);
      await pipeline.advance('Psalm two', useAi: true);
      expect(pipeline.latencyTimeouts, 2);
    });
  });
}
