import 'package:bnpb/services/ai/auto_tag_service.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LocalLlmService {
  _FakeLlm(this._response);
  final String _response;
  String? lastPrompt;

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
    lastPrompt = prompt;
    return _response;
  }
}

class _UnreadyLlm extends _FakeLlm {
  _UnreadyLlm() : super('');
  @override
  bool get isReady => false;
}

void main() {
  group('AutoTagService', () {
    test('parses a well-formed JSON array from the model', () async {
      final llm = _FakeLlm('["new_job","relocation","anxiety"]');
      final service = AutoTagService(llm);
      final tags = await service.suggestTags('Sarah moved for a new job.');
      expect(tags, ['new_job', 'relocation', 'anxiety']);
    });

    test('extracts the JSON array even with surrounding prose', () async {
      final llm = _FakeLlm('Sure! Here are tags: ["health","family"] done.');
      final service = AutoTagService(llm);
      final tags = await service.suggestTags("Dad's surgery went well.");
      expect(tags, ['health', 'family']);
    });

    test(
      'normalizes casing, punctuation, and spacing into snake_case',
      () async {
        final llm = _FakeLlm('["New Job!", "Re-location", "ANXIETY  "]');
        final service = AutoTagService(llm);
        final tags = await service.suggestTags('note');
        expect(tags, ['new_job', 're_location', 'anxiety']);
      },
    );

    test('deduplicates and caps at 6 tags', () async {
      final llm = _FakeLlm('["a","b","c","d","e","f","g","h","a"]');
      final service = AutoTagService(llm);
      final tags = await service.suggestTags('note');
      expect(tags.length, 6);
      expect(tags.toSet().length, 6);
    });

    test('returns empty list when output has no JSON array', () async {
      final llm = _FakeLlm('I cannot generate tags for that.');
      final service = AutoTagService(llm);
      expect(await service.suggestTags('note'), isEmpty);
    });

    test(
      'returns empty list for empty input without invoking the model',
      () async {
        final llm = _FakeLlm('["should_not_appear"]');
        final service = AutoTagService(llm);
        expect(await service.suggestTags('   '), isEmpty);
        expect(llm.lastPrompt, isNull);
      },
    );

    test('throws StateError when LLM is not ready', () async {
      final service = AutoTagService(_UnreadyLlm());
      expect(
        () => service.suggestTags('something'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
