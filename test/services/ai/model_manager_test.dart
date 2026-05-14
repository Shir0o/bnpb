import 'dart:async';
import 'dart:io';

import 'package:bnpb/services/ai/background_downloader.dart';
import 'package:bnpb/services/ai/model_manager.dart';
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

/// Test downloader that writes [payload] to disk in one chunk and emits a
/// single progress event before completing. Behavior is configurable via
/// [error] (throw mid-stream) and [emitWithoutFile] (close without ever
/// writing a file, to exercise the "completed without producing a file"
/// guard in ModelManager).
class _FakeDownloader implements BackgroundDownloader {
  _FakeDownloader({this.payload, this.error, this.emitWithoutFile = false});
  final List<int>? payload;
  final Object? error;
  final bool emitWithoutFile;

  String? lastUrl;
  Map<String, String> lastHeaders = const {};

  @override
  Stream<DownloadProgressEvent> download({
    required String url,
    required String savedDir,
    required String filename,
    Map<String, String> headers = const {},
  }) async* {
    lastUrl = url;
    lastHeaders = headers;
    if (error != null) {
      yield const DownloadProgressEvent(0, 100);
      throw error!;
    }
    if (!emitWithoutFile && payload != null) {
      final file = File(p.join(savedDir, filename));
      await file.writeAsBytes(payload!);
    }
    yield DownloadProgressEvent(payload?.length ?? 0, payload?.length ?? 0);
  }
}

void main() {
  group('ModelManager.ensureFreeSpace', () {
    test('passes when probe reports ample free space', () async {
      final manager = ModelManager(
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => 10000,
      );
      await manager.ensureFreeSpace(path: '/tmp');
    });

    test('throws InsufficientStorageException when probe reports too little',
        () async {
      final manager = ModelManager(
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => 500,
      );
      await expectLater(
        manager.ensureFreeSpace(path: '/tmp'),
        throwsA(isA<InsufficientStorageException>()),
      );
    });

    test('passes (no-op) when probe returns null (unknown free space)',
        () async {
      final manager = ModelManager(
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => null,
      );
      await manager.ensureFreeSpace(path: '/tmp');
    });

    test('InsufficientStorageException.toString surfaces a friendly message',
        () {
      final e = InsufficientStorageException(
        requiredBytes: 3500 * 1024 * 1024,
        freeBytes: 1024 * 1024 * 1024,
      );
      final msg = e.toString();
      expect(msg, contains('3.4 GB'));
      expect(msg, contains('1.0 GB'));
      expect(msg, contains('free some space'));
    });
  });

  group('ModelManager.download', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_manager_test_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('writes payload to target file and renames atomically', () async {
      final downloader = _FakeDownloader(payload: [1, 2, 3, 4]);
      final manager = ModelManager(
        downloader: downloader,
        modelFilename: 'test.bin',
        freeSpaceProbe: (_) async => null,
      );

      final events = await manager.download().toList();
      expect(events, isNotEmpty);

      final path = await manager.modelPath();
      final f = File(path);
      expect(await f.exists(), isTrue);
      expect(await f.readAsBytes(), [1, 2, 3, 4]);
      // No leftover .part file.
      expect(await File('$path.part').exists(), isFalse);
    });

    test('forwards huggingFaceToken as Bearer auth header', () async {
      final downloader = _FakeDownloader(payload: [0]);
      final manager = ModelManager(
        downloader: downloader,
        modelFilename: 'test.bin',
        freeSpaceProbe: (_) async => null,
      );

      await manager.download(huggingFaceToken: 'hf_abc').drain<void>();
      expect(downloader.lastHeaders['Authorization'], 'Bearer hf_abc');
    });

    test('emits InsufficientStorageException when disk is too tight', () async {
      final downloader = _FakeDownloader(payload: [1, 2, 3]);
      final manager = ModelManager(
        downloader: downloader,
        modelFilename: 'test.bin',
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => 100,
      );

      await expectLater(
        manager.download(),
        emitsError(isA<InsufficientStorageException>()),
      );
    });

    test('propagates downloader errors without renaming a partial', () async {
      final downloader = _FakeDownloader(error: StateError('boom'));
      final manager = ModelManager(
        downloader: downloader,
        modelFilename: 'test.bin',
        freeSpaceProbe: (_) async => null,
      );

      await expectLater(
        manager.download(),
        emitsThrough(emitsError(isA<StateError>())),
      );
      final path = await manager.modelPath();
      expect(await File(path).exists(), isFalse);
    });

    test('errors if downloader completes without producing a file', () async {
      final downloader = _FakeDownloader(emitWithoutFile: true);
      final manager = ModelManager(
        downloader: downloader,
        modelFilename: 'test.bin',
        freeSpaceProbe: (_) async => null,
      );

      await expectLater(
        manager.download(),
        emitsThrough(emitsError(isA<StateError>())),
      );
    });
  });
}
