import 'package:bnpb/services/ai/local_llm_service.dart';

/// Shared [LocalLlmService] fake used by widget tests that exercise the
/// Ready-to-log AI fallback path. Returns a configurable canned response.
class FakePipelineLlm implements LocalLlmService {
  FakePipelineLlm(this.response, {this.delay = Duration.zero});
  final String response;
  final Duration delay;
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
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return response;
  }
}
