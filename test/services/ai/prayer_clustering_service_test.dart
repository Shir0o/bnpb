import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:bnpb/services/ai/prayer_clustering_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LocalLlmService {
  _FakeLlm(this._response, {this.ready = true});
  final String _response;
  final bool ready;
  String? lastPrompt;
  int callCount = 0;

  @override
  bool get isReady => ready;

  @override
  Future<void> load(String modelPath) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async {
    lastPrompt = prompt;
    callCount++;
    return _response;
  }
}

PrayerRequest _req(int id, String description) {
  return PrayerRequest(
    id: id,
    participantIds: const ['contact-a'],
    description: description,
    status: PrayerRequestStatus.pending,
    requestedAt: DateTime(2026, 5, 1),
  );
}

void main() {
  group('PrayerClusteringService', () {
    test('returns empty when fewer than two requests', () async {
      final llm = _FakeLlm('[]');
      final service = PrayerClusteringService(llm);
      expect(await service.cluster([]), isEmpty);
      expect(await service.cluster([_req(1, 'Anything')]), isEmpty);
      expect(llm.callCount, 0);
    });

    test('parses well-formed JSON clusters', () async {
      final llm = _FakeLlm('''
[
  {"theme":"Health","indices":[0,2]},
  {"theme":"Work","indices":[1]}
]''');
      final service = PrayerClusteringService(llm);
      final clusters = await service.cluster([
        _req(10, 'Mom recovering from surgery'),
        _req(11, 'Job interview Thursday'),
        _req(12, 'Dad chemo next week'),
      ]);
      expect(clusters, hasLength(2));
      expect(clusters[0].theme, 'Health');
      expect(clusters[0].requestIds, [10, 12]);
      expect(clusters[1].theme, 'Work');
      expect(clusters[1].requestIds, [11]);
    });

    test('throws when LLM not ready', () async {
      final llm = _FakeLlm('[]', ready: false);
      final service = PrayerClusteringService(llm);
      expect(
        () => service.cluster([_req(1, 'a'), _req(2, 'b')]),
        throwsStateError,
      );
    });

    test('returns empty list when JSON is malformed', () async {
      final llm = _FakeLlm('not even close to json');
      final service = PrayerClusteringService(llm);
      final clusters = await service.cluster([
        _req(1, 'a'),
        _req(2, 'b'),
      ]);
      expect(clusters, isEmpty);
    });

    test('ignores out-of-range and duplicate indices', () async {
      final llm = _FakeLlm('''
[
  {"theme":"Family","indices":[0,1,1,99,-1]},
  {"theme":"Other","indices":[0,2]}
]''');
      final service = PrayerClusteringService(llm);
      final clusters = await service.cluster([
        _req(1, 'a'),
        _req(2, 'b'),
        _req(3, 'c'),
      ]);
      expect(clusters, hasLength(2));
      expect(clusters[0].requestIds, [1, 2]);
      // First cluster claimed index 0; second cluster only keeps 2.
      expect(clusters[1].requestIds, [3]);
    });

    test('clamps long theme labels', () async {
      final longTheme = 'x' * 200;
      final llm = _FakeLlm('[{"theme":"$longTheme","indices":[0,1]}]');
      final service = PrayerClusteringService(llm);
      final clusters = await service.cluster([
        _req(1, 'a'),
        _req(2, 'b'),
      ]);
      expect(clusters, hasLength(1));
      expect(clusters[0].theme.length, lessThanOrEqualTo(40));
    });

    test('prompt contains only descriptions, no participant or status data',
        () async {
      final llm = _FakeLlm('[]');
      final service = PrayerClusteringService(llm);
      await service.cluster([
        PrayerRequest(
          id: 1,
          participantIds: const ['secret-contact-id'],
          description: 'Mom recovery',
          status: PrayerRequestStatus.pending,
          requestedAt: DateTime(2024, 1, 1),
          category: 'health-private',
          reflectionNotes: 'do not leak this note',
        ),
        PrayerRequest(
          id: 2,
          participantIds: const ['another-secret'],
          description: 'Job search',
          status: PrayerRequestStatus.answered,
          requestedAt: DateTime(2024, 2, 2),
        ),
      ]);
      final prompt = llm.lastPrompt!;
      expect(prompt, contains('Mom recovery'));
      expect(prompt, contains('Job search'));
      expect(prompt, isNot(contains('secret-contact-id')));
      expect(prompt, isNot(contains('another-secret')));
      expect(prompt, isNot(contains('do not leak this note')));
      expect(prompt, isNot(contains('health-private')));
      expect(prompt, isNot(contains('2024')));
      expect(prompt, isNot(contains('answered')));
    });

    test('caches results for identical inputs', () async {
      final llm = _FakeLlm('[{"theme":"Health","indices":[0,1]}]');
      final service = PrayerClusteringService(llm);
      final input = [_req(1, 'a'), _req(2, 'b')];
      await service.cluster(input);
      await service.cluster(input);
      await service.cluster([_req(1, 'a'), _req(2, 'b')]);
      expect(llm.callCount, 1);
    });

    test('cache invalidates when descriptions change', () async {
      final llm = _FakeLlm('[{"theme":"Health","indices":[0,1]}]');
      final service = PrayerClusteringService(llm);
      await service.cluster([_req(1, 'a'), _req(2, 'b')]);
      await service.cluster([_req(1, 'a-edited'), _req(2, 'b')]);
      expect(llm.callCount, 2);
    });

    test('invalidateCache forces a fresh call', () async {
      final llm = _FakeLlm('[{"theme":"Health","indices":[0,1]}]');
      final service = PrayerClusteringService(llm);
      final input = [_req(1, 'a'), _req(2, 'b')];
      await service.cluster(input);
      service.invalidateCache();
      await service.cluster(input);
      expect(llm.callCount, 2);
    });

    test('drops clusters with no valid indices', () async {
      final llm = _FakeLlm('[{"theme":"Bogus","indices":[99]}]');
      final service = PrayerClusteringService(llm);
      final clusters = await service.cluster([
        _req(1, 'a'),
        _req(2, 'b'),
      ]);
      expect(clusters, isEmpty);
    });
  });
}
