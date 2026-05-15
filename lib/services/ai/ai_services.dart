import 'package:flutter_gemma/flutter_gemma.dart';

import 'ai_feature_gate.dart';
import 'auto_tag_service.dart';
import 'embedding_service.dart';
import 'follow_up_suggestion_service.dart';
import 'interaction_summary_service.dart';
import 'local_llm_service.dart';
import 'outreach_draft_service.dart';
import 'prayer_clustering_service.dart';
import 'semantic_search_service.dart';
import 'model_manager.dart';

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

  /// True only when the user has opted in AND the model is loaded.
  Future<bool> isReady() async {
    if (!await _gate.isEnabled()) return false;
    return _llm.isReady;
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
