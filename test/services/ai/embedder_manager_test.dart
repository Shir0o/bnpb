import 'dart:async';
import 'dart:io';

import 'package:bnpb/services/ai/background_downloader.dart';
import 'package:bnpb/services/ai/embedder_manager.dart';
import 'package:bnpb/services/ai/model_manager.dart'
    show InsufficientStorageException;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Per-URL payload downloader. Writes the payload mapped to each URL to disk
/// when that URL is requested. Used to exercise the two-leg download flow.
class _MultiUrlDownloader implements BackgroundDownloader {
  _MultiUrlDownloader(this.payloads);
  final Map<String, List<int>> payloads;
  final List<String> requestedUrls = [];

  @override
  Stream<DownloadProgressEvent> download({
    required String url,
    required String savedDir,
    required String filename,
    Map<String, String> headers = const {},
  }) async* {
    requestedUrls.add(url);
    final bytes = payloads[url];
    if (bytes == null) {
      throw StateError('Unexpected URL in test downloader: $url');
    }
    await File(p.join(savedDir, filename)).writeAsBytes(bytes);
    yield DownloadProgressEvent(bytes.length, bytes.length);
  }

  @override
  void dispose() {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('embedder_manager_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('status() reports absent when neither file exists', () async {
    final manager = EmbedderManager(
      downloader: _MultiUrlDownloader(const {}),
      freeSpaceProbe: (_) async => null,
    );
    expect(await manager.status(), EmbedderStatus.absent);
  });

  test('download writes both files and status() flips to ready', () async {
    const modelUrl = 'https://example.test/model.tflite';
    const tokUrl = 'https://example.test/tok.model';
    final downloader = _MultiUrlDownloader({
      modelUrl: [1, 2, 3, 4],
      tokUrl: [9, 8, 7],
    });
    final manager = EmbedderManager(
      downloader: downloader,
      modelUrl: modelUrl,
      tokenizerUrl: tokUrl,
      modelFilename: 'm.tflite',
      tokenizerFilename: 'tok.model',
      freeSpaceProbe: (_) async => null,
    );

    await manager.download().drain<void>();
    expect(downloader.requestedUrls, [modelUrl, tokUrl]);
    expect(await manager.status(), EmbedderStatus.ready);
    expect(await File(await manager.modelPath()).readAsBytes(), [1, 2, 3, 4]);
    expect(await File(await manager.tokenizerPath()).readAsBytes(), [9, 8, 7]);
  });

  test('status() returns partial when one file is missing', () async {
    final manager = EmbedderManager(
      downloader: _MultiUrlDownloader(const {}),
      modelFilename: 'm.tflite',
      tokenizerFilename: 'tok.model',
      freeSpaceProbe: (_) async => null,
    );
    // Hand-create only the model file.
    final modelFile = File(await manager.modelPath());
    await modelFile.create(recursive: true);
    await modelFile.writeAsBytes([0]);
    expect(await manager.status(), EmbedderStatus.partial);
  });

  test('delete() removes both files', () async {
    const modelUrl = 'https://example.test/model.tflite';
    const tokUrl = 'https://example.test/tok.model';
    final manager = EmbedderManager(
      downloader: _MultiUrlDownloader({
        modelUrl: [1],
        tokUrl: [2],
      }),
      modelUrl: modelUrl,
      tokenizerUrl: tokUrl,
      modelFilename: 'm.tflite',
      tokenizerFilename: 'tok.model',
      freeSpaceProbe: (_) async => null,
    );
    await manager.download().drain<void>();
    expect(await manager.status(), EmbedderStatus.ready);
    await manager.delete();
    expect(await manager.status(), EmbedderStatus.absent);
  });

  test('ensureFreeSpace throws when probe reports too little', () async {
    final manager = EmbedderManager(
      downloader: _MultiUrlDownloader(const {}),
      requiredFreeBytes: 1000,
      freeSpaceProbe: (_) async => 100,
    );
    await expectLater(
      manager.ensureFreeSpace(path: tempDir.path),
      throwsA(isA<InsufficientStorageException>()),
    );
  });
}
