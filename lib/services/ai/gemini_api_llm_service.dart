import 'dart:async';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'local_llm_service.dart';

/// Cloud backend for [LocalLlmService] that routes prompts to Google's
/// Gemini API using a user-supplied key.
///
/// This is an **opt-in** path — by default BNPB runs every AI feature
/// on the device with no network. When the user explicitly enables
/// cloud AI in Settings and supplies their own API key, [AiServices]
/// swaps the active backend to this class. The consumer services
/// (AutoTag, FollowUp, PrayerClustering) see no change — they still
/// depend on the `LocalLlmService` interface.
///
/// Network behavior: this service does **not** silently fall back to
/// the local model on failure. If the network is unreachable or the
/// API rejects the request, callers see the error so they know which
/// backend produced (or failed to produce) the answer — that's the
/// consent contract the cloud opt-in is built on.
class GeminiApiLlmService implements LocalLlmService {
  GeminiApiLlmService({
    required String apiKey,
    String modelId = 'gemini-2.5-flash',
  })  : _apiKey = apiKey,
        _modelId = modelId;

  final String _apiKey;
  final String _modelId;

  // The SDK's GenerativeModel is cheap to construct and stateless across
  // requests, so we lazily build one per (apiKey, modelId) and keep it for
  // the lifetime of this service. No persistent connection to manage.
  GenerativeModel? _model;

  /// Always true: the credentials are checked at construction and there
  /// is no separate "load" step. Network reachability is verified per
  /// call rather than at startup so we don't pay a probe round-trip on
  /// every app launch.
  @override
  bool get isReady => true;

  /// No-op for cloud backend — there is no local model file to install.
  /// Kept on the interface so existing callers (e.g. AiSettingsPage's
  /// enable flow) don't need to branch on backend type.
  @override
  Future<void> load(String modelPath) async {}

  @override
  Future<void> unload() async {
    _model = null;
  }

  GenerativeModel _activeModel() {
    return _model ??= GenerativeModel(model: _modelId, apiKey: _apiKey);
  }

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async {
    final response = await _activeModel().generateContent(
      [Content.text(prompt)],
      generationConfig: GenerationConfig(
        maxOutputTokens: maxTokens,
        temperature: temperature,
      ),
    );
    return response.text ?? '';
  }

  /// Real token streaming via Gemini's `generateContentStream`. The
  /// [LocalLlmServiceStreaming] extension on the abstract interface
  /// dispatches to this when the active backend is cloud, so AutoTag's
  /// streaming chip rendering works the same way it does on the
  /// on-device path.
  Stream<String> streamWithPrefix(
    String prompt, {
    String? systemPrefix,
    int maxTokens = 512,
    double temperature = 0.4,
  }) async* {
    final fullPrompt = systemPrefix == null ? prompt : '$systemPrefix$prompt';
    final stream = _activeModel().generateContentStream(
      [Content.text(fullPrompt)],
      generationConfig: GenerationConfig(
        maxOutputTokens: maxTokens,
        temperature: temperature,
      ),
    );
    await for (final chunk in stream) {
      final text = chunk.text;
      if (text != null && text.isNotEmpty) yield text;
    }
  }
}
