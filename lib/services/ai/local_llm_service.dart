import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;

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

/// Streaming + prefix-pinned generation. Implemented as an extension so
/// existing fake `LocalLlmService` instances (5+ test files) keep compiling
/// without changes. Default behavior yields a single chunk from
/// [LocalLlmService.generate]; the production [FlutterGemmaLlmService] gets
/// real token streaming and KV-cache reuse via its
/// [FlutterGemmaLlmService.streamWithPrefix] hook.
extension LocalLlmServiceStreaming on LocalLlmService {
  Stream<String> generateStream(
    String prompt, {
    String? systemPrefix,
    int maxTokens = 512,
    double temperature = 0.4,
  }) async* {
    final self = this;
    if (self is FlutterGemmaLlmService) {
      yield* self.streamWithPrefix(
        prompt,
        systemPrefix: systemPrefix,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      return;
    }
    final full = systemPrefix == null ? prompt : '$systemPrefix$prompt';
    yield await self.generate(
      full,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }
}

/// Production-backed implementation using `flutter_gemma` ^0.12.6.
///
/// One [InferenceModel] is held for the lifetime of the service. The
/// non-streaming [generate] path still creates a fresh single-shot session so
/// per-call `temperature` is honored. The streaming + prefix-pinned path
/// (see [streamWithPrefix]) keeps a long-lived [InferenceModelSession] keyed
/// by `systemPrefix`, so the KV cache for the (usually long) prompt prefix
/// is reused across calls — this is the win that turns AutoTag's
/// first-token latency from seconds into hundreds of ms on warm taps.
class FlutterGemmaLlmService implements LocalLlmService {
  FlutterGemmaLlmService({this.contextWindowTokens = 2048});

  final int contextWindowTokens;

  InferenceModel? _model;
  String? _loadedPath;

  // Warm session state. Keyed by the exact prefix string; if the next call
  // passes a different prefix we close and recreate. `_pinnedPrefixSent`
  // tracks whether the prefix has been included in any addQueryChunk call
  // on this session yet — see the "lazy prefix encoding" note on
  // [streamWithPrefix] for why we delay it instead of seeding at create.
  InferenceModelSession? _pinnedSession;
  String? _pinnedPrefix;
  double? _pinnedTemperature;
  bool _pinnedPrefixSent = false;

  @override
  bool get isReady => _model != null;

  @override
  Future<void> load(String modelPath) async {
    if (_loadedPath == modelPath && _model != null) return;
    await unload();

    final sw = Stopwatch()..start();
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromFile(modelPath)
        .install();
    // Prefer GPU. flutter_gemma falls back GPU → CPU automatically if the
    // device can't satisfy the request, so this is safe to default-on.
    // Without this hint the engine picks XNNPack CPU, which on a Pixel
    // takes ~1 token/sec for gemma-3n-e2b-int4 — unusable.
    _model = await FlutterGemma.getActiveModel(
      maxTokens: contextWindowTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    _loadedPath = modelPath;
    if (kDebugMode) {
      debugPrint(
        '[ai.perf] llm.load ms=${sw.elapsedMilliseconds} '
        'path=${p.basename(modelPath)}',
      );
    }
  }

  @override
  Future<void> unload() async {
    await _closePinnedSession();
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

  Future<void> _closePinnedSession() async {
    final s = _pinnedSession;
    _pinnedSession = null;
    _pinnedPrefix = null;
    _pinnedTemperature = null;
    _pinnedPrefixSent = false;
    if (s == null) return;
    try {
      await s.close();
    } catch (_) {}
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

  /// Streaming + prefix-pinned generation. Public so the
  /// [LocalLlmServiceStreaming] extension can dispatch to it; call sites
  /// should use `generateStream(...)` on the abstract interface, not this
  /// method directly.
  ///
  /// When [systemPrefix] is non-null, a session keyed to that prefix is
  /// kept alive across calls. Same prefix → KV-cache reuse via the
  /// session's prior-turn history; different prefix → close + recreate.
  ///
  /// **Lazy prefix encoding.** The prefix is NOT pre-added at session
  /// creation. Instead, the first call on a fresh pinned session sends
  /// `prefix + prompt` as a single chunk, and subsequent calls send only
  /// the per-call `prompt`. This matters because flutter_gemma forwards
  /// each `addQueryChunk` to MediaPipe's chunked-prefill path, and on
  /// int4-quantized small models like `gemma-3n-e2b-int4` chunked prefill
  /// (prefix then suffix as separate chunks) can produce slightly
  /// different attention values than a single prefill of the same
  /// concatenation — enough to make the cold call latch onto the last
  /// few-shot example as its answer instead of generating new tags. The
  /// single-prefill-on-first-call layout sidesteps that while still
  /// reusing the prefix's KV cache for every subsequent call on the
  /// same session.
  ///
  /// flutter_gemma 0.12.6 only accepts `temperature` at session creation,
  /// so the warm-session path locks temperature to the first call's
  /// value — a later call passing a different temperature with the same
  /// prefix is logged but does NOT rebuild the session (that'd defeat
  /// the warm cache). AutoTag uses 0.2 for every call, so this is fine.
  Stream<String> streamWithPrefix(
    String prompt, {
    String? systemPrefix,
    int maxTokens = 512,
    double temperature = 0.4,
  }) async* {
    final model = _model;
    if (model == null) {
      throw StateError('LocalLlmService.generateStream called before load()');
    }

    InferenceModelSession session;
    bool isPinned;
    bool sendPrefixInline = false;
    if (systemPrefix == null) {
      session = await model.createSession(
        temperature: temperature,
        topK: 40,
        topP: 0.95,
      );
      isPinned = false;
    } else if (_pinnedSession != null && _pinnedPrefix == systemPrefix) {
      session = _pinnedSession!;
      isPinned = true;
      // Already-active pinned session: prefix lives in prior-turn KV cache.
      sendPrefixInline = !_pinnedPrefixSent;
      if (kDebugMode) {
        debugPrint(
          '[ai.perf] llm.warmSession.reuse '
          'prefixHash=${_prefixHash(systemPrefix)}',
        );
        if (_pinnedTemperature != null &&
            (_pinnedTemperature! - temperature).abs() > 1e-6) {
          debugPrint(
            '[ai.perf] llm.warmSession.tempMismatch '
            'pinned=$_pinnedTemperature got=$temperature '
            '(temperature is locked to first call on the pinned session)',
          );
        }
      }
    } else {
      await _closePinnedSession();
      final sw = Stopwatch()..start();
      session = await model.createSession(
        temperature: temperature,
        topK: 40,
        topP: 0.95,
      );
      _pinnedSession = session;
      _pinnedPrefix = systemPrefix;
      _pinnedTemperature = temperature;
      _pinnedPrefixSent = false;
      isPinned = true;
      sendPrefixInline = true;
      if (kDebugMode) {
        debugPrint(
          '[ai.perf] llm.warmSession.create '
          'prefixHash=${_prefixHash(systemPrefix)} '
          'ms=${sw.elapsedMilliseconds}',
        );
      }
    }

    final chunk = sendPrefixInline ? '$systemPrefix$prompt' : prompt;
    await session.addQueryChunk(Message.text(text: chunk, isUser: true));
    if (sendPrefixInline && isPinned) {
      _pinnedPrefixSent = true;
    }
    bool completed = false;
    try {
      await for (final chunk in session.getResponseAsync()) {
        yield chunk;
      }
      completed = true;
    } finally {
      // If the consumer broke out of the await loop early (e.g. AutoTag
      // saw the closing `]` and doesn't need the trailing prose the model
      // would still emit), tell the engine to stop. On a pinned session
      // this is essential — without it the next call would be queued
      // behind ongoing generation.
      if (!completed) {
        try {
          await session.stopGeneration();
        } catch (_) {}
      }
      if (!isPinned) {
        try {
          await session.close();
        } catch (_) {}
      }
    }
  }

  String _prefixHash(String s) => s.hashCode.toRadixString(16);
}
