import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/contact.dart';
import '../security_service.dart';
import 'ai_feature_gate.dart';
import 'auto_tag_service.dart';
import 'embedding_service.dart';
import 'embedder_manager.dart';
import 'follow_up_suggestion_service.dart';
import 'gemini_api_llm_service.dart';
import 'interaction_summary_service.dart';
import 'local_llm_service.dart';
import 'model_manager.dart';
import 'outreach_draft_service.dart';
import 'prayer_clustering_service.dart';
import 'semantic_search_service.dart';

/// Process-wide accessor for AI services so call sites don't need to thread
/// dependencies through widget constructors. Mirrors the
/// `ReminderCoordinator()` access pattern used elsewhere in the codebase.
///
/// Tests can replace the singletons via [debugOverride].
class AiServices {
  AiServices._();
  static final AiServices _instance = AiServices._();
  factory AiServices() => _instance;

  LocalLlmService _llm = FlutterGemmaLlmService();
  AiFeatureGate _gate = AiFeatureGate();
  EmbeddingService _embedding = FlutterGemmaEmbeddingService();
  SemanticSearchService? _semanticSearchCache;
  FollowUpSuggestionService? _followUpCache;
  AutoTagService? _autoTagCache;
  InteractionSummaryService? _summaryCache;
  OutreachDraftService? _outreachCache;
  PrayerClusteringService? _prayerClusteringCache;

  LocalLlmService get llm => _llm;
  AiFeatureGate get gate => _gate;
  EmbeddingService get embedding => _embedding;
  SemanticSearchService get semanticSearch =>
      _semanticSearchCache ??= FlutterGemmaSemanticSearchService(_embedding);
  FollowUpSuggestionService get followUp =>
      _followUpCache ??= FollowUpSuggestionService(_llm);
  AutoTagService get autoTag => _autoTagCache ??= AutoTagService(_llm);
  InteractionSummaryService get interactionSummary =>
      _summaryCache ??= InteractionSummaryService(_llm);
  OutreachDraftService get outreach =>
      _outreachCache ??= OutreachDraftService(_llm);
  PrayerClusteringService get prayerClustering =>
      _prayerClusteringCache ??= PrayerClusteringService(_llm);

  bool _semanticInitialized = false;
  Future<void>? _semanticInitInFlight;

  /// Initializes the semantic search vector store (loads the persisted
  /// SQLite + rebuilds the in-memory HNSW index). Performs a one-time
  /// from-scratch rebuild only when the persisted store is empty. Safe
  /// to call repeatedly from multiple call sites — concurrent calls
  /// share the same in-flight future.
  Future<void> ensureSemanticIndex(List<Contact> contacts) {
    if (_semanticInitialized) return Future.value();
    return _semanticInitInFlight ??= () async {
      try {
        final dir = await getApplicationSupportDirectory();
        final dbPath = p.join(dir.path, 'semantic_vectors.db');
        await semanticSearch.initialize(dbPath);
        final actual = await semanticSearch.documentCount();
        if (actual == 0) {
          await semanticSearch.rebuildIndex(contacts);
        }
        _semanticInitialized = true;
      } finally {
        _semanticInitInFlight = null;
      }
    }();
  }

  /// True only when the user has opted in AND the active backend is ready.
  Future<bool> isReady() async {
    if (!await _gate.isEnabled()) return false;
    return _llm.isReady;
  }

  /// Swaps the active LLM backend to match the user's current preference
  /// (local Gemma vs cloud Gemini). Idempotent — calling with the
  /// already-active backend type is a no-op aside from picking up a
  /// changed API key. Cached AI services are invalidated so the next
  /// access wires them up against the new backend.
  Future<void> refreshBackend() async {
    final backend = await _gate.backend();
    if (backend == AiBackend.cloud) {
      final apiKey = await SecurityService().getGeminiApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        // User asked for cloud but never supplied a key — fall back to
        // local so existing call sites that null-check `isReady` still
        // give a coherent answer. AiSettingsPage's toggle UI is what
        // surfaces this state to the user.
        await _setBackend(FlutterGemmaLlmService());
        return;
      }
      await _setBackend(GeminiApiLlmService(apiKey: apiKey));
      return;
    }
    await _setBackend(FlutterGemmaLlmService());
  }

  Future<void> _setBackend(LocalLlmService next) async {
    if (identical(_llm, next)) return;
    if (_llm.runtimeType == next.runtimeType &&
        _llm is GeminiApiLlmService &&
        next is GeminiApiLlmService) {
      // Same backend type — only the API key could have changed. Drop
      // the previous cached SDK model so the next call rebuilds with
      // the new key.
      await _llm.unload();
    }
    try {
      await _llm.unload();
    } catch (_) {}
    _llm = next;
    _followUpCache = null;
    _autoTagCache = null;
    _summaryCache = null;
    _outreachCache = null;
    _prayerClusteringCache = null;
  }

  /// Initializes the underlying flutter_gemma runtime and, if AI features
  /// are enabled and the model exists on disk, loads it. Safe to call once
  /// at app startup. Failures are swallowed so AI never blocks app launch.
  Future<void> maybeInitialize() async {
    try {
      await FlutterGemma.initialize();
    } catch (_) {
      return;
    }
    if (!await _gate.isEnabled()) return;
    // Pick the right backend before doing any backend-specific setup.
    // Cloud backend has nothing to load locally; local backend needs
    // the model file on disk.
    await refreshBackend();
    if (_llm is FlutterGemmaLlmService) {
      try {
        final manager = ModelManager();
        final status = await manager.status();
        if (status == ModelStatus.ready) {
          await _llm.load(await manager.modelPath());
        }
        manager.dispose();
      } catch (_) {
        // Best-effort: leave the model unloaded; the AI settings page can
        // re-attempt loading and surface errors there.
      }
    }
    try {
      final embedderMgr = EmbedderManager();
      if (await embedderMgr.status() == EmbedderStatus.ready) {
        await _embedding.load(
          modelPath: await embedderMgr.modelPath(),
          tokenizerPath: await embedderMgr.tokenizerPath(),
        );
        // One-shot warmup so the user's first Ask query doesn't pay the
        // embedder cold-start cost.
        if (_embedding.isReady) {
          try {
            final sw = Stopwatch()..start();
            await _embedding.embed('warmup');
            if (kDebugMode) {
              debugPrint(
                  '[ai.perf] embedder.warmup ms=${sw.elapsedMilliseconds}');
            }
          } catch (_) {
            // Warmup is best-effort; a real query will surface any error.
          }
        }
      }
      // Deliberately not calling embedderMgr.dispose(): the downloader
      // returned by defaultBackgroundDownloader() backs onto shared native
      // plugin state, so disposing it here would break any other in-flight
      // download (e.g. a user-initiated LLM download still running).
    } catch (_) {
      // Best-effort, same reasoning as the LLM block above.
    }
  }

  /// Test-only seam.
  void debugOverride({
    LocalLlmService? llm,
    AiFeatureGate? gate,
    EmbeddingService? embedding,
    SemanticSearchService? semanticSearch,
  }) {
    if (llm != null) {
      _llm = llm;
      _followUpCache = null;
      _autoTagCache = null;
      _summaryCache = null;
      _outreachCache = null;
      _prayerClusteringCache = null;
    }
    if (gate != null) _gate = gate;
    if (embedding != null) {
      _embedding = embedding;
      _semanticSearchCache = null;
    }
    if (semanticSearch != null) _semanticSearchCache = semanticSearch;
  }
}
