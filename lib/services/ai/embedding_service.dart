import 'package:flutter_gemma/flutter_gemma.dart';

/// Thin abstraction over an on-device text-embedding backend.
///
/// The default implementation wraps `flutter_gemma`'s embedder, but we depend
/// on the interface — not the package — so tests can inject a fake and so we
/// can swap to a different embedder runtime without rippling through callers.
abstract class EmbeddingService {
  /// Whether the underlying embedder is loaded and ready.
  bool get isReady;

  /// Embedding vector dimensionality once [isReady] is true. Returns `null`
  /// while unloaded.
  int? get dimension;

  /// Loads the embedder. Idempotent across the same (modelPath, tokenizerPath)
  /// pair. Setup of the model + tokenizer files on disk is the caller's
  /// concern — this method just brings the active embedder online.
  Future<void> load({required String modelPath, required String tokenizerPath});

  /// Releases embedder resources. Safe to call when not loaded.
  Future<void> unload();

  /// Encodes [text] into an embedding vector. Throws [StateError] if the
  /// embedder is not loaded.
  Future<List<double>> embed(String text);

  /// Batch variant. Default impl falls back to sequential [embed] calls; a
  /// backend with a vectorized path is free to override.
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final out = <List<double>>[];
    for (final text in texts) {
      out.add(await embed(text));
    }
    return out;
  }
}

/// Production-backed implementation using `flutter_gemma` ^0.12.6.
///
/// Embedder model + tokenizer files are downloaded and managed by a separate
/// EmbedderManager (follow-up PR). This service expects the files to already
/// exist on disk when [load] is called.
class FlutterGemmaEmbeddingService implements EmbeddingService {
  EmbeddingModel? _model;
  String? _loadedModelPath;
  String? _loadedTokenizerPath;
  int? _dimension;

  @override
  bool get isReady => _model != null;

  @override
  int? get dimension => _dimension;

  @override
  Future<void> load({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    if (_model != null &&
        _loadedModelPath == modelPath &&
        _loadedTokenizerPath == tokenizerPath) {
      return;
    }
    await unload();

    await FlutterGemma.installEmbedder()
        .modelFromFile(modelPath)
        .tokenizerFromFile(tokenizerPath)
        .install();
    final model = await FlutterGemmaPlugin.instance.createEmbeddingModel();
    _model = model;
    _loadedModelPath = modelPath;
    _loadedTokenizerPath = tokenizerPath;
    _dimension = await model.getDimension();
  }

  @override
  Future<void> unload() async {
    final model = _model;
    _model = null;
    _loadedModelPath = null;
    _loadedTokenizerPath = null;
    _dimension = null;
    if (model == null) return;
    try {
      await model.close();
    } catch (_) {
      // Best-effort cleanup; embedder resources reclaim on process exit.
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    final model = _model;
    if (model == null) {
      throw StateError('EmbeddingService.embed called before load()');
    }
    return model.generateEmbedding(text);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final model = _model;
    if (model == null) {
      throw StateError('EmbeddingService.embedBatch called before load()');
    }
    return model.generateEmbeddings(texts);
  }
}
