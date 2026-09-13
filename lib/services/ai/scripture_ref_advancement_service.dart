import 'dart:convert';

import 'local_llm_service.dart';
import 'scripture_ref.dart';

/// Uses the on-device LLM to extract a scripture reference from free-form
/// interaction notes that the regex path (see [ScriptureRef.tryAdvance])
/// cannot parse.
///
/// The model returns the CURRENT ref in the series; the service calls
/// [ScriptureRef.advance] to produce the next ref the user should log.
/// Only the note text itself is sent to the model. Output stays on device.
class ScriptureRefAdvancementService {
  ScriptureRefAdvancementService(this._llm);

  final LocalLlmService _llm;

  /// Tries to extract and advance a scripture ref from [text].
  Future<ScriptureRef?> advance(String? text) async {
    final current = await extract(text);
    return current?.advance();
  }

  /// Extracts the CURRENT scripture ref from [text] without advancing it.
  Future<ScriptureRef?> extract(String? text) async {
    if (text == null || text.isEmpty) return null;
    if (_llm.isReady == false) {
      throw StateError('LLM is not ready');
    }
    final prompt = _buildPrompt(text);
    final raw = await _llm.generate(prompt, maxTokens: 96, temperature: 0.0);
    return _parseCurrent(raw);
  }

  String _buildPrompt(String note) {
    final escaped = jsonEncode(note);
    return '''
You extract the CURRENT scripture reference from a free-form note about an
interaction. Output ONLY a single JSON object, no prose. Shape:
{
  "book": "<book code: Psa, Gen, Matt, 1Cor, etc.>",
  "start": <int, first chapter>,
  "end":   <int, last chapter; equals start for a single chapter>,
  "verseStart": <int, optional, only for verse-style refs like "Gen 1:1">,
  "verseEnd":   <int, optional, defaults to verseStart>
}

Return the CURRENT reference, not the next one. For "Psa 117" return
"start":117, "end":117. For "Psa 115-116" return "start":115, "end":116.

If the note contains no recognizable scripture reference, output: null

Note: $escaped
Output:''';
  }

  ScriptureRef? _parseCurrent(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final slice = raw.substring(start, end + 1);

    final dynamic decoded;
    try {
      decoded = jsonDecode(slice);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final book = decoded['book'];
    final startVal = _parseInt(decoded['start']);
    final endVal = _parseInt(decoded['end']) ?? startVal;
    if (book is! String || book.isEmpty || startVal == null || endVal == null) {
      return null;
    }
    if (startVal <= 0 || endVal < startVal) return null;

    final verseStart = _parseInt(decoded['verseStart']);
    final verseEnd = _parseInt(decoded['verseEnd']) ?? verseStart;

    return ScriptureRef(
      book: book,
      start: startVal,
      end: endVal,
      verseStart: verseStart,
      verseEnd: verseEnd,
    );
  }

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return num.tryParse(v.trim())?.round();
    return null;
  }
}
