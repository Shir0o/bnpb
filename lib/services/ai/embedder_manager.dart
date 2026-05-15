import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'background_downloader.dart';
import 'model_manager.dart' show FreeSpaceProbe, InsufficientStorageException;

/// Status of the on-device embedder assets. Both the tflite model and the
/// sentencepiece tokenizer must be present for [EmbedderStatus.ready].
enum EmbedderStatus { absent, partial, ready, corrupt }

class EmbedderDownloadProgress {
  final int bytesReceived;
  final int? bytesTotal;
  const EmbedderDownloadProgress(this.bytesReceived, this.bytesTotal);
  double? get fraction => bytesTotal == null || bytesTotal == 0
      ? null
      : bytesReceived / bytesTotal!;
}

/// Manages download, storage, and integrity of the Gecko text embedder
/// (tflite model + sentencepiece tokenizer).
///
/// Mirrors [ModelManager] in shape but with two key differences:
///   * Two files, not one. Progress is summed across both legs so the UI
///     can show a single bar.
///   * Embedder assets are open (Kaggle), so no auth-token plumbing.
class EmbedderManager {
  EmbedderManager({
    BackgroundDownloader? downloader,
    String modelUrl = _defaultModelUrl,
    String tokenizerUrl = _defaultTokenizerUrl,
    String modelFilename = _defaultModelFilename,
    String tokenizerFilename = _defaultTokenizerFilename,
    String? expectedModelSha256,
    String? expectedTokenizerSha256,
    int requiredFreeBytes = _defaultRequiredFreeBytes,
    FreeSpaceProbe? freeSpaceProbe,
  })  : _downloader = downloader ?? defaultBackgroundDownloader(),
        _modelUrl = modelUrl,
        _tokenizerUrl = tokenizerUrl,
        _modelFilename = modelFilename,
        _tokenizerFilename = tokenizerFilename,
        _expectedModelSha256 = expectedModelSha256,
        _expectedTokenizerSha256 = expectedTokenizerSha256,
        _requiredFreeBytes = requiredFreeBytes,
        _freeSpaceProbe = freeSpaceProbe;

  // Gecko 110M English text-embedder from the litert-community HuggingFace
  // mirror. We use the 256-token int8-quantized variant: 256 tokens covers a
  // typical interaction (date + summary + notes + location) without padding,
  // and int8 quantization shrinks the model ~4x with negligible retrieval-
  // quality impact for this corpus.
  static const String _defaultModelUrl =
      'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_256_quant.tflite?download=true';
  static const String _defaultTokenizerUrl =
      'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model?download=true';
  static const String _defaultModelFilename = 'gecko_110m_en.tflite';
  static const String _defaultTokenizerFilename = 'gecko_sentencepiece.model';
  // ~110 MB combined + headroom for both `.part` files and FS overhead.
  static const int _defaultRequiredFreeBytes = 250 * 1024 * 1024;

  final BackgroundDownloader _downloader;
  final String _modelUrl;
  final String _tokenizerUrl;
  final String _modelFilename;
  final String _tokenizerFilename;
  final String? _expectedModelSha256;
  final String? _expectedTokenizerSha256;
  final int _requiredFreeBytes;
  final FreeSpaceProbe? _freeSpaceProbe;

  Future<Directory> _aiDir() async {
    final dir = await getApplicationSupportDirectory();
    final aiDir = Directory(p.join(dir.path, 'ai_models'));
    if (!await aiDir.exists()) {
      await aiDir.create(recursive: true);
    }
    return aiDir;
  }

  Future<File> _modelFile() async =>
      File(p.join((await _aiDir()).path, _modelFilename));

  Future<File> _tokenizerFile() async =>
      File(p.join((await _aiDir()).path, _tokenizerFilename));

  Future<String> modelPath() async => (await _modelFile()).path;
  Future<String> tokenizerPath() async => (await _tokenizerFile()).path;

  Future<EmbedderStatus> status() async {
    final modelOk = await _modelFile().then((f) => f.exists());
    final tokOk = await _tokenizerFile().then((f) => f.exists());
    if (!modelOk && !tokOk) return EmbedderStatus.absent;
    if (!modelOk || !tokOk) return EmbedderStatus.partial;
    if (_expectedModelSha256 != null) {
      if (await _sha256(await _modelFile()) != _expectedModelSha256) {
        return EmbedderStatus.corrupt;
      }
    }
    if (_expectedTokenizerSha256 != null) {
      if (await _sha256(await _tokenizerFile()) != _expectedTokenizerSha256) {
        return EmbedderStatus.corrupt;
      }
    }
    return EmbedderStatus.ready;
  }

  Future<int?> freeSpaceBytes({String? path}) async {
    final probe = _freeSpaceProbe;
    if (probe == null) return null;
    final probePath = path ?? (await _aiDir()).path;
    return probe(probePath);
  }

  Future<void> ensureFreeSpace({String? path}) async {
    final free = await freeSpaceBytes(path: path);
    if (free != null && free < _requiredFreeBytes) {
      throw InsufficientStorageException(
        requiredBytes: _requiredFreeBytes,
        freeBytes: free,
      );
    }
  }

  /// Hardcoded estimate of the combined download size, used as the progress
  /// bar denominator so the bar advances monotonically across both legs
  /// (~114 MB Gecko_256_quant + ~5 MB sentencepiece, with a little headroom).
  /// If the actual transfer exceeds this estimate we clamp at the total so
  /// the bar never reads above 100%.
  static const int _combinedDownloadEstimate = 120 * 1024 * 1024;

  /// Downloads both files sequentially, emitting a single combined progress
  /// stream so the UI can render one bar. Each leg writes to a `.part` file
  /// and renames on success.
  Stream<EmbedderDownloadProgress> download() {
    late final StreamController<EmbedderDownloadProgress> controller;
    StreamSubscription<DownloadProgressEvent>? innerSub;
    Completer<void>? activeLeg;
    var cancelled = false;

    controller = StreamController<EmbedderDownloadProgress>(
      onCancel: () async {
        cancelled = true;
        await innerSub?.cancel();
        // The downloader's listener won't fire onDone/onError after a
        // subscription cancel, so we have to manually unblock any in-flight
        // leg waiter — otherwise run() would suspend forever and the
        // background task would leak.
        final leg = activeLeg;
        if (leg != null && !leg.isCompleted) {
          leg.completeError(const _DownloadCancelled());
        }
      },
    );

    Future<void> downloadOne({
      required String url,
      required File target,
      required int priorBytes,
    }) async {
      if (cancelled) throw const _DownloadCancelled();
      final partial = File('${target.path}.part');
      if (await partial.exists()) await partial.delete();
      final completer = Completer<void>();
      activeLeg = completer;
      innerSub = _downloader
          .download(
        url: url,
        savedDir: target.parent.path,
        filename: p.basename(partial.path),
      )
          .listen(
        (event) {
          final received = priorBytes + event.bytesReceived;
          // Use the static combined estimate as the denominator so the bar
          // advances smoothly across both legs instead of jumping back when
          // the second leg discovers its own content-length. Clamp to keep
          // the displayed fraction <= 1.0 if the real total exceeds the
          // estimate.
          final clamped = received > _combinedDownloadEstimate
              ? _combinedDownloadEstimate
              : received;
          controller.add(
              EmbedderDownloadProgress(clamped, _combinedDownloadEstimate));
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      try {
        await completer.future;
      } finally {
        activeLeg = null;
      }
      if (cancelled) throw const _DownloadCancelled();
      if (!await partial.exists()) {
        throw StateError('Download completed without producing $url');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    }

    Future<void> run() async {
      try {
        await ensureFreeSpace();
        final modelTarget = await _modelFile();
        final tokTarget = await _tokenizerFile();

        await downloadOne(
          url: _modelUrl,
          target: modelTarget,
          priorBytes: 0,
        );
        if (_expectedModelSha256 != null) {
          final actual = await _sha256(modelTarget);
          if (actual != _expectedModelSha256) {
            await modelTarget.delete();
            throw StateError(
                'Embedder model checksum mismatch (expected $_expectedModelSha256)');
          }
        }

        final modelBytes = await modelTarget.length();
        await downloadOne(
          url: _tokenizerUrl,
          target: tokTarget,
          priorBytes: modelBytes,
        );
        if (_expectedTokenizerSha256 != null) {
          final actual = await _sha256(tokTarget);
          if (actual != _expectedTokenizerSha256) {
            await tokTarget.delete();
            throw StateError(
                'Embedder tokenizer checksum mismatch (expected $_expectedTokenizerSha256)');
          }
        }
        await controller.close();
      } on _DownloadCancelled {
        // Consumer cancelled the subscription mid-flight. The controller is
        // already being torn down by the framework; nothing more to do.
        if (!controller.isClosed) await controller.close();
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
    final model = await _modelFile();
    final tok = await _tokenizerFile();
    if (await model.exists()) await model.delete();
    if (await tok.exists()) await tok.delete();
  }

  Future<void> deletePartial() async {
    final model = await _modelFile();
    final tok = await _tokenizerFile();
    for (final p in ['${model.path}.part', '${tok.path}.part']) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// No-op: [BackgroundDownloader] instances returned by
  /// `defaultBackgroundDownloader()` back onto shared native plugin state
  /// (e.g. flutter_downloader's WorkManager registration), so disposing the
  /// downloader from a single short-lived manager would break any other
  /// in-flight downloads. Callers that inject their own downloader own its
  /// lifecycle.
  void dispose() {}
}

/// Sentinel error used internally to unwind a cancelled download cleanly.
class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
