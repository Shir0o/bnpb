import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'local_llm_service.dart';

// Compile-time flag for diagnostic logs that may include user note content
// (raw model output, prompt echoes). Off in every build by default so that
// even in debug builds note text never lands in logcat unless a developer
// opts in explicitly:
//
//   flutter run --dart-define=AI_VERBOSE=true
//
// Independent from `kDebugMode`. The release-build tree-shaker eliminates
// guarded branches because this is a compile-time const.
const bool _kAiVerboseLogs = bool.fromEnvironment('AI_VERBOSE');

/// Suggests tags for a free-text note (interaction body, prayer request,
/// general contact note) using the on-device LLM.
///
/// Returns a small set of normalized lowercase tags. Output is constrained
/// by prompt + post-processing so a small model can't run away with prose.
class AutoTagService {
  AutoTagService(this._llm);

  final LocalLlmService _llm;

  static const int _maxTags = 6;
  static const int _maxTagLength = 24;

  // Hoisted so we don't recompile on every streamed chunk.
  static final RegExp _quotedStringRegex = RegExp(r'"((?:[^"\\]|\\.)*)"');

  Future<List<String>> suggestTags(String note) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return const [];
    if (!_llm.isReady) {
      throw StateError('AutoTagService called before LLM was loaded');
    }

    // Funnel through the streaming path so all callers benefit from the
    // pinned warm session on FlutterGemmaLlmService. For fake LLMs the
    // stream emits a single chunk and this collapses back to the original
    // behavior.
    final stream = suggestTagsStream(trimmed);
    List<String> latest = const [];
    await for (final tags in stream) {
      latest = tags;
    }
    return latest;
  }

  /// Streaming variant. Emits incrementally-growing tag lists as the model
  /// produces tokens. The final emit is the same value that
  /// [suggestTags] would have returned.
  Stream<List<String>> suggestTagsStream(String note) async* {
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      yield const [];
      return;
    }
    if (!_llm.isReady) {
      throw StateError('AutoTagService called before LLM was loaded');
    }

    final sw = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint(
        '[ai.perf] autotag.generate.start noteChars=${trimmed.length}',
      );
    }

    final stream = _llm.generateStream(
      _buildSuffix(trimmed),
      systemPrefix: _systemPrefix,
      maxTokens: 96,
      temperature: 0.2,
    );

    final buffer = StringBuffer();
    bool firstToken = true;
    bool firstChip = true;
    List<String> lastEmit = const [];

    await for (final chunk in stream) {
      if (chunk.isEmpty) continue;
      if (firstToken) {
        firstToken = false;
        if (kDebugMode) {
          debugPrint(
            '[ai.perf] autotag.firstToken ms=${sw.elapsedMilliseconds}',
          );
        }
      }
      buffer.write(chunk);
      final raw = buffer.toString();
      final parsed = _parsePartial(raw);
      if (!listEquals(parsed, lastEmit)) {
        if (firstChip && parsed.isNotEmpty) {
          firstChip = false;
          if (kDebugMode) {
            debugPrint(
              '[ai.perf] autotag.firstChip ms=${sw.elapsedMilliseconds}',
            );
          }
        }
        lastEmit = parsed;
        yield parsed;
      }
      // Early stop: once the model has closed the JSON array, the answer
      // is complete. Anything after `]` is trailing prose we'd discard,
      // and on a slow decode path that prose can add 20+ seconds.
      // Breaking here cancels the inner subscription, which routes
      // through FlutterGemmaLlmService.streamWithPrefix's finally and
      // calls session.stopGeneration() on the engine.
      final openIdx = raw.indexOf('[');
      if (openIdx >= 0 && raw.indexOf(']', openIdx + 1) >= 0) {
        if (kDebugMode) {
          debugPrint(
            '[ai.perf] autotag.earlyStop ms=${sw.elapsedMilliseconds}',
          );
        }
        break;
      }
    }

    final finalTags = _parse(buffer.toString());
    if (!listEquals(finalTags, lastEmit)) {
      yield finalTags;
    }
    if (kDebugMode) {
      debugPrint(
        '[ai.perf] autotag.done ms=${sw.elapsedMilliseconds} '
        'tagCount=${finalTags.length}',
      );
    }
    if (kDebugMode && _kAiVerboseLogs) {
      // Raw model output. Useful for diagnosing the model echoing a
      // few-shot example, JSON malformation, etc., but it can contain
      // fragments of the user's note text, so it stays behind the
      // verbose flag instead of firing on every debug run.
      final raw = buffer.toString();
      final clipped = raw.length > 240 ? '${raw.substring(0, 240)}…' : raw;
      debugPrint('[ai.perf] autotag.raw "${clipped.replaceAll('\n', '\\n')}"');
    }
  }

  // System prefix — rules + few-shot examples. Kept identical across calls
  // so [FlutterGemmaLlmService] can pin a session keyed to this string and
  // reuse its KV cache. Touching this string invalidates the warm cache, so
  // do not interpolate per-call data here.
  static const String _systemPrefix = '''
You extract short topic tags from personal-relationship notes.
Rules:
- Output ONLY a JSON array of 1-6 lowercase strings, no prose.
- Each tag is 1-3 words, snake_case, under 24 chars.
- Prefer topics, life events, relationships, emotions. Skip names.

Note: "Caught up with Sarah, she just got a new job at a hospital and is anxious about moving."
Tags: ["new_job","relocation","anxiety","career"]

Note: "Dad's surgery went well, family is grateful."
Tags: ["health","surgery","family","gratitude"]

''';

  String _buildSuffix(String note) => 'Note: ${_escape(note)}\nTags:';

  // jsonEncode wraps the string in quotes and escapes embedded quotes,
  // newlines, and control characters — safer than hand-rolled replacement.
  String _escape(String s) => jsonEncode(s);

  // Parse a possibly-incomplete JSON array, returning whatever well-formed
  // string elements have been emitted so far.
  List<String> _parsePartial(String raw) {
    final start = raw.indexOf('[');
    if (start < 0) return const [];
    final end = raw.indexOf(']', start + 1);
    if (end >= 0) {
      // Closed array — defer to the strict parser.
      return _parse(raw);
    }
    // Open array: scan for completed quoted strings.
    final body = raw.substring(start + 1);
    final out = <String>{};
    final matches = _quotedStringRegex.allMatches(body);
    for (final m in matches) {
      String? decoded;
      try {
        decoded = jsonDecode('"${m.group(1)}"') as String;
      } catch (_) {
        continue;
      }
      final tag = _normalize(decoded);
      if (tag.isEmpty) continue;
      out.add(tag);
      if (out.length >= _maxTags) break;
    }
    return out.toList(growable: false);
  }

  List<String> _parse(String raw) {
    final start = raw.indexOf('[');
    final end = raw.indexOf(']', start + 1);
    if (start < 0 || end < 0) return const [];
    final slice = raw.substring(start, end + 1);
    try {
      final decoded = jsonDecode(slice);
      if (decoded is! List) return const [];
      final out = <String>{};
      for (final item in decoded) {
        if (item is! String) continue;
        final tag = _normalize(item);
        if (tag.isEmpty) continue;
        out.add(tag);
        if (out.length >= _maxTags) break;
      }
      return out.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String _normalize(String raw) {
    final lower = raw.toLowerCase().trim();
    final sanitized = lower
        .replaceAll(RegExp(r'[^a-z0-9_\s-]'), '')
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (sanitized.length > _maxTagLength) {
      return sanitized.substring(0, _maxTagLength);
    }
    return sanitized;
  }
}
