import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Manages download, storage, and integrity of the Gemma 3n model file.
///
/// The model is kept in the app's support directory (not user-visible) and
/// not in any backup-able location, since it can always be re-downloaded.
class ModelManager {
  ModelManager({
    http.Client? httpClient,
    String modelUrl = _defaultModelUrl,
    String modelFilename = _defaultModelFilename,
    String? expectedSha256,
    int requiredFreeBytes = _defaultRequiredFreeBytes,
    FreeSpaceProbe? freeSpaceProbe,
  })  : _http = httpClient ?? http.Client(),
        _modelUrl = modelUrl,
        _modelFilename = modelFilename,
        _expectedSha256 = expectedSha256,
        _requiredFreeBytes = requiredFreeBytes,
        _freeSpaceProbe = freeSpaceProbe ?? _defaultFreeSpaceProbe;

  // Gemma 3n E2B int4 task file on Hugging Face. The repo requires accepting
  // Google's Gemma terms once per HF account; the runtime download happens
  // with the user's HF token (or anonymous if Google opens public access).
  // Confirm the latest filename before shipping — Google rotates these.
  static const String _defaultModelUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task';
  static const String _defaultModelFilename = 'gemma-3n-e2b-int4.task';
  // ~3 GB model + headroom for the `.part` file and FS overhead.
  static const int _defaultRequiredFreeBytes = 3500 * 1024 * 1024;

  final http.Client _http;
  final String _modelUrl;
  final String _modelFilename;
  final String? _expectedSha256;
  final int _requiredFreeBytes;
  final FreeSpaceProbe _freeSpaceProbe;

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    final aiDir = Directory(p.join(dir.path, 'ai_models'));
    if (!await aiDir.exists()) {
      await aiDir.create(recursive: true);
    }
    return File(p.join(aiDir.path, _modelFilename));
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
  /// directory has less than [_requiredFreeBytes] free. A `null` probe
  /// result (unknown free space) is treated as a pass — we'd rather attempt
  /// the download and fail at write time than block on missing info.
  Future<void> ensureFreeSpace({String? path}) async {
    final free = await freeSpaceBytes(path: path);
    if (free != null && free < _requiredFreeBytes) {
      throw InsufficientStorageException(
        requiredBytes: _requiredFreeBytes,
        freeBytes: free,
      );
    }
  }

  /// Downloads the model with progress events. Atomic: writes to a `.part`
  /// file and renames on success, so partial downloads never look ready.
  Stream<ModelDownloadProgress> download({String? huggingFaceToken}) async* {
    await ensureFreeSpace();
    final target = await _modelFile();
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    final request = http.Request('GET', Uri.parse(_modelUrl));
    if (huggingFaceToken != null && huggingFaceToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $huggingFaceToken';
    }

    final response = await _http.send(request);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw HttpException(
        'Hugging Face rejected the download (HTTP ${response.statusCode}). '
        'Make sure you have accepted the Gemma license on the model page '
        'and provided a valid access token.',
        uri: Uri.parse(_modelUrl),
      );
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'Model download failed: HTTP ${response.statusCode}',
        uri: Uri.parse(_modelUrl),
      );
    }

    final total = response.contentLength;
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield ModelDownloadProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (_expectedSha256 != null) {
      final actual = await _sha256(partial);
      if (actual != _expectedSha256) {
        await partial.delete();
        throw StateError('Model checksum mismatch (expected $_expectedSha256)');
      }
    }
    // On Windows, rename fails if the destination already exists, so
    // explicitly remove any prior copy first.
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
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

  void dispose() => _http.close();
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
