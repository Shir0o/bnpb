import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/ai/ai_services.dart';
import 'package:bnpb/services/ai/semantic_search_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FakeSemanticSearchService implements SemanticSearchService {
  int initializeCalls = 0;
  final List<List<Contact>> rebuilds = [];

  @override
  SemanticIndexStatus get status => SemanticIndexStatus.ready;

  @override
  Object? get lastError => null;

  @override
  Future<void> initialize(String dbPath) async {
    initializeCalls += 1;
  }

  @override
  Future<void> rebuildIndex(
    List<Contact> contacts, {
    void Function(int done, int total)? onProgress,
  }) async {
    rebuilds.add(contacts);
    onProgress?.call(1, 1);
  }

  @override
  Future<List<SemanticMatch>> query(
    String text, {
    required Map<String, Contact> contactsById,
    int topK = 10,
  }) async =>
      const [];

  @override
  Future<void> clear() async {}

  // Non-empty so ensureSemanticIndex skips its own first-run rebuild.
  @override
  Future<int> documentCount() async => 3;

  @override
  Future<void> close() async {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_reindex_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await AiServices().shutdown();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('reindexSemantic initializes the store and rebuilds every time',
      () async {
    final fake = _FakeSemanticSearchService();
    AiServices().debugOverride(semanticSearch: fake);
    final contacts = [Contact(id: 'c1', firstName: 'Ana', lastName: 'B')];

    final progress = <(int, int)>[];
    await AiServices().reindexSemantic(
      contacts,
      onProgress: (done, total) => progress.add((done, total)),
    );
    // A second tap rebuilds again even though the store is now initialized.
    await AiServices().reindexSemantic(contacts);

    expect(fake.initializeCalls, 1);
    expect(fake.rebuilds, [contacts, contacts]);
    expect(progress, [(1, 1)]);
  });
}
