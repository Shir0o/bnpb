import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/ai/ai_services.dart';
import 'package:bnpb/services/ai/semantic_search_service.dart';

class _FakeSemanticSearchService implements SemanticSearchService {
  int closeCalls = 0;

  @override
  SemanticIndexStatus get status => SemanticIndexStatus.ready;

  @override
  Object? get lastError => null;

  @override
  Future<void> initialize(String dbPath) async {}

  @override
  Future<void> rebuildIndex(
    List<Contact> contacts, {
    void Function(int done, int total)? onProgress,
  }) async {}

  @override
  Future<List<SemanticMatch>> query(
    String text, {
    required Map<String, Contact> contactsById,
    int topK = 10,
  }) async =>
      const [];

  @override
  Future<void> clear() async {}

  @override
  Future<int> documentCount() async => 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

void main() {
  group('AiServices.shutdown', () {
    test('is a no-op when the semantic store was never accessed', () async {
      // Fresh process state — no override installed.
      await AiServices().shutdown(); // should not throw
    });

    test('forwards to SemanticSearchService.close when cached', () async {
      final fake = _FakeSemanticSearchService();
      AiServices().debugOverride(semanticSearch: fake);
      // Touching the getter populates the cache so shutdown sees it.
      // ignore: unnecessary_statements
      AiServices().semanticSearch;

      await AiServices().shutdown();

      expect(fake.closeCalls, 1);
    });

    test('swallows errors from close()', () async {
      AiServices().debugOverride(semanticSearch: _ThrowingService());
      // ignore: unnecessary_statements
      AiServices().semanticSearch;
      await AiServices().shutdown(); // should not throw
    });
  });
}

class _ThrowingService extends _FakeSemanticSearchService {
  @override
  Future<void> close() async => throw StateError('boom');
}
