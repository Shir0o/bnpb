import 'dart:async';

import 'scripture_ref.dart';
import 'scripture_ref_advancement_service.dart';

/// Combines the regex path ([ScriptureRef.tryAdvance]) with the LLM path
/// ([ScriptureRefAdvancementService.advance]) for the Ready-to-log card.
///
/// The pipeline tries regex first (free, sub-millisecond). On a miss, if
/// the caller has opted in via [useAi] (which the caller derives from
/// [AiFeatureGate]), it falls back to the LLM. The LLM call is wrapped in
/// a hard [latencyCap] — if the model exceeds the cap, the call is
/// abandoned and the pipeline returns null so the tile is skipped.
///
/// The pipeline owns a process-wide counter ([latencyTimeouts]) so the
/// host page can surface a "model is too slow" diagnostic if timeouts
/// accumulate.
class ScriptureRefAdvancementPipeline {
  ScriptureRefAdvancementPipeline(
    this._service, {
    this.latencyCap = const Duration(milliseconds: 150),
  });

  final ScriptureRefAdvancementService _service;
  final Duration latencyCap;

  int _latencyTimeouts = 0;

  /// Total number of LLM calls abandoned because they exceeded [latencyCap]
  /// since this pipeline was constructed. Diagnostic only; the caller is
  /// expected to read it when surfacing UX diagnostics, not for behavior.
  int get latencyTimeouts => _latencyTimeouts;

  /// Tries to advance [text] to the next reference. Returns null if no
  /// ref can be determined (regex miss + AI miss/timeout/disabled).
  ///
  /// When [useAi] is false, the LLM is never consulted, even on a regex
  /// miss — the user has explicitly disabled AI for this feature.
  Future<ScriptureRef?> advance(String? text, {required bool useAi}) async {
    if (text == null || text.isEmpty) return null;

    final regexHit = ScriptureRef.tryAdvance(text);
    if (regexHit != null) return regexHit;
    if (!useAi) return null;

    try {
      return await _service.advance(text).timeout(latencyCap);
    } on TimeoutException {
      _latencyTimeouts++;
      return null;
    } catch (_) {
      // LLM not ready, parse failure, etc. — surfaced as null. The
      // service already logs / handles internally where appropriate.
      return null;
    }
  }
}
