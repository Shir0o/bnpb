import 'dart:convert';

import '../../models/prayer_request.dart';
import 'local_llm_service.dart';

class PrayerCluster {
  final String theme;
  final List<int> requestIds;

  const PrayerCluster({required this.theme, required this.requestIds});
}

/// Groups prayer requests into thematic clusters using the on-device LLM.
///
/// Privacy: only the request `description` text is sent to the model. No
/// participant IDs, contact names, timestamps, or status are included in
/// the prompt — the model sees prayer text and nothing else.
///
/// Results are cached in memory keyed by a content hash so repeated renders
/// don't re-run the model.
class PrayerClusteringService {
  PrayerClusteringService(this._llm);

  final LocalLlmService _llm;

  static const int _maxClusters = 8;
  static const int _maxThemeLength = 40;
  static const int _maxRequestsPerCall = 60;

  String? _cacheKey;
  List<PrayerCluster>? _cacheValue;

  /// Groups [requests] by theme. Returns an empty list when there are fewer
  /// than two requests (nothing to cluster) or when the LLM returns nothing
  /// parseable.
  Future<List<PrayerCluster>> cluster(List<PrayerRequest> requests) async {
    if (requests.length < 2) return const [];
    if (!_llm.isReady) {
      throw StateError('PrayerClusteringService called before LLM was loaded');
    }

    // Cap to avoid blowing the prompt budget. Callers pass pending-first;
    // the tail is the least useful anyway (oldest answered/archived).
    final scoped = requests.length > _maxRequestsPerCall
        ? requests.sublist(0, _maxRequestsPerCall)
        : requests;

    final key = _keyFor(scoped);
    if (key == _cacheKey && _cacheValue != null) return _cacheValue!;

    final prompt = _buildPrompt(scoped);
    final raw = await _llm.generate(
      prompt,
      maxTokens: 512,
      temperature: 0.2,
    );

    final clusters = _parse(raw, scoped);
    _cacheKey = key;
    _cacheValue = clusters;
    return clusters;
  }

  void invalidateCache() {
    _cacheKey = null;
    _cacheValue = null;
  }

  String _keyFor(List<PrayerRequest> requests) {
    final buf = StringBuffer();
    for (final r in requests) {
      buf
        ..write(r.id ?? r.syncId)
        ..write('|')
        ..write(r.description)
        ..write('\n');
    }
    return buf.toString();
  }

  String _buildPrompt(List<PrayerRequest> requests) {
    final lines = StringBuffer();
    for (var i = 0; i < requests.length; i++) {
      lines
        ..write(i)
        ..write(': ')
        ..writeln(jsonEncode(requests[i].description));
    }

    return '''
You group prayer requests by theme.
Rules:
- Output ONLY a JSON array of objects, no prose.
- Each object: "theme" (short label, under $_maxThemeLength chars; prefer
  Health, Work, Family, Relationships, Faith, Finances, Guidance, Other,
  but invent a label if none fit), "indices" (array of integers referencing
  the input lines below).
- Every input index appears in exactly one cluster.
- At most $_maxClusters clusters total.
- Clusters with a single request are fine.

Input lines (index: description):
${lines.toString().trimRight()}

Output:''';
  }

  List<PrayerCluster> _parse(String raw, List<PrayerRequest> requests) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final slice = raw.substring(start, end + 1);

    final dynamic decoded;
    try {
      decoded = jsonDecode(slice);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];

    final seenIndex = <int>{};
    final clusters = <PrayerCluster>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final theme = _string(item['theme']);
      final indicesRaw = item['indices'];
      if (theme.isEmpty || indicesRaw is! List) continue;

      final ids = <int>[];
      for (final idx in indicesRaw) {
        final i = _int(idx);
        if (i == null || i < 0 || i >= requests.length) continue;
        if (!seenIndex.add(i)) continue;
        final id = requests[i].id;
        if (id != null) ids.add(id);
      }
      if (ids.isEmpty) continue;

      final trimmedTheme = theme.length > _maxThemeLength
          ? theme.substring(0, _maxThemeLength)
          : theme;
      clusters.add(PrayerCluster(theme: trimmedTheme, requestIds: ids));
      if (clusters.length >= _maxClusters) break;
    }
    return clusters;
  }

  String _string(dynamic v) => v is String ? v.trim() : '';

  int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return num.tryParse(v.trim())?.round();
    return null;
  }
}
