import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show ModelType;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'background_downloader.dart';

/// Status of the local LLM model on disk.
enum ModelStatus { absent, downloading, ready, corrupt }

class ModelDownloadProgress {
  final int bytesReceived;
  final int? bytesTotal;
  const ModelDownloadProgress(this.bytesReceived, this.bytesTotal);
  double? get fraction => bytesTotal == null || bytesTotal == 0
      ? null
      : bytesReceived / bytesTotal!;
}

/// Thrown when the device does not have enough free space to download
/// the model. Carries enough info for a friendly user-facing message.
class InsufficientStorageException implements Exception {
  final int requiredBytes;
  final int? freeBytes;
  const InsufficientStorageException({
    required this.requiredBytes,
    required this.freeBytes,
  });
  @override
  String toString() {
    final freeGb = freeBytes == null
        ? 'unknown'
        : (freeBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1);
    final reqGb = (requiredBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return 'Need ~$reqGb GB free to download the AI model '
        '(currently $freeGb GB free). Please free some space and try again.';
  }
}

typedef FreeSpaceProbe = Future<int?> Function(String path);

/// Specification for an on-device model downloadable from Hugging Face.
class OnDeviceModelSpec {
  final String id;
  final String displayName;
  final String description;
  final String url;
  final String filename;
  final int requiredFreeBytes;
  final ModelType modelType;

  const OnDeviceModelSpec({
    required this.id,
    required this.displayName,
    required this.description,
    required this.url,
    required this.filename,
    required this.requiredFreeBytes,
    this.modelType = ModelType.gemmaIt,
  });

  String get sizeLabel =>
      '${(requiredFreeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  static const List<OnDeviceModelSpec> supportedModels = [
    OnDeviceModelSpec(
      id: 'gemma-3n-e2b-int4',
      displayName: 'Gemma 3n E2B (int4)',
      description: 'Default Google LiteRT model optimized for mobile',
      url:
          'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
      filename: 'gemma-3n-e2b-int4.task',
      requiredFreeBytes: 3500 * 1024 * 1024,
      modelType: ModelType.gemmaIt,
    ),
    OnDeviceModelSpec(
      id: 'llama-3.2-1b-it',
      displayName: 'Llama 3.2 1B Instruct',
      description: 'Meta lightweight model (~1.3 GB download)',
      url:
          'https://huggingface.co/litert-community/Llama-3.2-1B-Instruct/resolve/main/model.task',
      filename: 'llama-3.2-1b-it.task',
      requiredFreeBytes: 1500 * 1024 * 1024,
      modelType: ModelType.llama,
    ),
    OnDeviceModelSpec(
      id: 'llama-3.2-3b-it',
      displayName: 'Llama 3.2 3B Instruct',
      description: 'Meta balanced 3B model (~2.5 GB download)',
      url:
          'https://huggingface.co/litert-community/Llama-3.2-3B-Instruct/resolve/main/model.task',
      filename: 'llama-3.2-3b-it.task',
      requiredFreeBytes: 2800 * 1024 * 1024,
      modelType: ModelType.llama,
    ),
    OnDeviceModelSpec(
      id: 'qwen-2.5-1.5b-it',
      displayName: 'Qwen 2.5 1.5B Instruct',
      description: 'Alibaba high-speed multilingual model (~1.6 GB)',
      url:
          'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/model.task',
      filename: 'qwen-2.5-1.5b-it.task',
      requiredFreeBytes: 1800 * 1024 * 1024,
      modelType: ModelType.qwen,
    ),
    OnDeviceModelSpec(
      id: 'deepseek-r1-distill-1.5b',
      displayName: 'DeepSeek R1 Distill 1.5B',
      description: 'DeepSeek reasoning model (~1.6 GB download)',
      url:
          'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/model.task',
      filename: 'deepseek-r1-distill-1.5b.task',
      requiredFreeBytes: 1800 * 1024 * 1024,
      modelType: ModelType.deepSeek,
    ),
  ];

  static OnDeviceModelSpec forId(String? id) {
    if (id == null) return supportedModels.first;
    return supportedModels.firstWhere(
      (m) => m.id == id,
      orElse: () => supportedModels.first,
    );
  }
}

/// Manages download, storage, and integrity of on-device LLM model files.
///
/// The model is kept in the app's support directory (not user-visible) and
/// not in any backup-able location, since it can always be re-downloaded.
class ModelManager {
  ModelManager({
    BackgroundDownloader? downloader,
    OnDeviceModelSpec? modelSpec,
    String? modelUrl,
    String? modelFilename,
    String? expectedSha256,
    int? requiredFreeBytes,
    FreeSpaceProbe? freeSpaceProbe,
  })  : _downloader = downloader ?? defaultBackgroundDownloader(),
        _spec = modelSpec ?? OnDeviceModelSpec.supportedModels.first,
        _customUrl = modelUrl,
        _customFilename = modelFilename,
        _expectedSha256 = expectedSha256,
        _customRequiredFreeBytes = requiredFreeBytes,
        _freeSpaceProbe = freeSpaceProbe ?? _defaultFreeSpaceProbe;

  final BackgroundDownloader _downloader;
  final OnDeviceModelSpec _spec;
  final String? _customUrl;
  final String? _customFilename;
  final String? _expectedSha256;
  final int? _customRequiredFreeBytes;
  final FreeSpaceProbe _freeSpaceProbe;

  String get modelUrl => _customUrl ?? _spec.url;
  String get modelFilename => _customFilename ?? _spec.filename;
  int get requiredFreeBytes =>
      _customRequiredFreeBytes ?? _spec.requiredFreeBytes;
  ModelType get modelType => _spec.modelType;

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    final aiDir = Directory(p.join(dir.path, 'ai_models'));
    if (!await aiDir.exists()) {
      await aiDir.create(recursive: true);
    }
    return File(p.join(aiDir.path, modelFilename));
  }

  Future<String> modelPath() async => (await _modelFile()).path;

  Future<ModelStatus> status() async {
    final file = await _modelFile();
    if (!await file.exists()) return ModelStatus.absent;
    if (_expectedSha256 != null) {
      final actual = await _sha256(file);
      if (actual != _expectedSha256) return ModelStatus.corrupt;
    }
    return ModelStatus.ready;
  }

  /// Returns free bytes on the volume that will hold the model, or `null`
  /// if it cannot be determined on this platform. Injectable for tests.
  Future<int?> freeSpaceBytes({String? path}) async {
    final probePath = path ?? (await _modelFile()).parent.path;
    return _freeSpaceProbe(probePath);
  }

  /// Throws [InsufficientStorageException] if the volume backing the model
  /// directory has less than [requiredFreeBytes] free. A `null` probe
  /// result (unknown free space) is treated as a pass — we'd rather attempt
  /// the download and fail at write time than block on missing info.
  Future<void> ensureFreeSpace({String? path}) async {
    final free = await freeSpaceBytes(path: path);
    if (free != null && free < requiredFreeBytes) {
      throw InsufficientStorageException(
        requiredBytes: requiredFreeBytes,
        freeBytes: free,
      );
    }
  }

  /// Downloads the model with progress events. Atomic: writes to a `.part`
  /// file and renames on success, so partial downloads never look ready.
  /// On mobile, the underlying transfer continues if the app is
  /// backgrounded (URLSession on iOS, WorkManager on Android).
  Stream<ModelDownloadProgress> download({String? huggingFaceToken}) {
    late final StreamController<ModelDownloadProgress> controller;
    StreamSubscription<DownloadProgressEvent>? innerSub;

    controller = StreamController<ModelDownloadProgress>(
      onCancel: () async {
        await innerSub?.cancel();
      },
    );

    Future<void> run() async {
      try {
        await ensureFreeSpace();
        final target = await _modelFile();
        final partial = File('${target.path}.part');
        if (await partial.exists()) await partial.delete();

        final headers = <String, String>{};
        if (huggingFaceToken != null && huggingFaceToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $huggingFaceToken';
        }

        final completer = Completer<void>();
        innerSub = _downloader
            .download(
          url: modelUrl,
          savedDir: target.parent.path,
          filename: p.basename(partial.path),
          headers: headers,
        )
            .listen(
          (event) => controller.add(
            ModelDownloadProgress(event.bytesReceived, event.bytesTotal),
          ),
          onError: (Object e, StackTrace st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
        await completer.future;

        if (!await partial.exists()) {
          // The downloader reported completion but the file isn't there
          // (e.g. cancelled mid-flight before any bytes landed). Surface
          // this as an error rather than renaming a missing file.
          throw StateError('Download completed without producing a file');
        }

        if (_expectedSha256 != null) {
          final actual = await _sha256(partial);
          if (actual != _expectedSha256) {
            await partial.delete();
            throw StateError(
              'Model checksum mismatch (expected $_expectedSha256)',
            );
          }
        }
        // On Windows, rename fails if the destination already exists, so
        // explicitly remove any prior copy first.
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
        await controller.close();
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }

    run();
    return controller.stream;
  }

  Future<void> delete() async {
    final file = await _modelFile();
    if (await file.exists()) await file.delete();
  }

  /// Removes the `.part` file left behind by a cancelled or failed download.
  /// Safe to call when no partial exists.
  Future<void> deletePartial() async {
    final target = await _modelFile();
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  void dispose() => _downloader.dispose();
}

/// Default free-space probe. Uses the `disk_space_plus` plugin, which
/// goes through native platform APIs (`StatFs` on Android,
/// `NSURL.volumeAvailableCapacity` on iOS/macOS, `GetDiskFreeSpaceEx`
/// on Windows). Returns `null` if the plugin is unavailable on the
/// current platform so the check effectively no-ops rather than blocking
/// the download.
Future<int?> _defaultFreeSpaceProbe(String path) async {
  try {
    final freeMb = await DiskSpacePlus().getFreeDiskSpaceForPath(path);
    if (freeMb == null) return null;
    return (freeMb * 1024 * 1024).round();
  } catch (_) {
    return null;
  }
}
