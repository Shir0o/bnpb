import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

/// Thin abstraction over an on-device LLM backend.
///
/// The default implementation wraps `flutter_gemma`, but we depend on the
/// interface — not the package — so tests can inject a fake and so we can
/// swap to a different runtime (MediaPipe, llama.cpp, Apple Foundation Models)
/// without rippling through callers.
abstract class LocalLlmService {
  /// Whether the underlying model is loaded and ready to generate.
  bool get isReady;

  /// Loads the model from [modelPath]. Idempotent: calling twice with the
  /// same path is a no-op.
  Future<void> load(String modelPath);

  /// Releases model resources. Safe to call when not loaded.
  Future<void> unload();

  /// Generates a single response for [prompt]. Throws [StateError] if the
  /// model is not loaded.
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  });
}

/// Production-backed implementation using `flutter_gemma` ^0.12.6.
///
/// One [InferenceModel] is held for the lifetime of the service. Each
/// `generate()` call creates a fresh single-shot session so that
/// `temperature` can vary per call (the session-level parameter is the only
/// way to control sampling in this version).
class FlutterGemmaLlmService implements LocalLlmService {
  FlutterGemmaLlmService({this.contextWindowTokens = 2048});

  final int contextWindowTokens;

  InferenceModel? _model;
  String? _loadedPath;

  @override
  bool get isReady => _model != null;

  @override
  Future<void> load(String modelPath) async {
    if (_loadedPath == modelPath && _model != null) return;
    await unload();

    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromFile(modelPath)
        .install();
    _model = await FlutterGemma.getActiveModel(maxTokens: contextWindowTokens);
    _loadedPath = modelPath;
  }

  @override
  Future<void> unload() async {
    final model = _model;
    _model = null;
    _loadedPath = null;
    if (model == null) return;
    try {
      await model.close();
    } catch (_) {
      // Best-effort cleanup — model resources are reclaimed on process exit
      // regardless.
    }
  }

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async {
    final model = _model;
    if (model == null) {
      throw StateError('LocalLlmService.generate called before load()');
    }
    final session = await model.createSession(
      temperature: temperature,
      topK: 40,
      topP: 0.95,
    );
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }
}
