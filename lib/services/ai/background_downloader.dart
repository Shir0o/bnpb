import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// One progress event emitted by a [BackgroundDownloader] while a download
/// is in flight. `bytesTotal` may be null if the source did not report a
/// content length, or if the underlying implementation only knows the
/// percentage (e.g. `flutter_downloader`).
class DownloadProgressEvent {
  final int bytesReceived;
  final int? bytesTotal;
  const DownloadProgressEvent(this.bytesReceived, this.bytesTotal);

  double? get fraction => bytesTotal == null || bytesTotal == 0
      ? null
      : bytesReceived / bytesTotal!;
}

/// Streams bytes from a URL onto disk. Implementations differ in how
/// resilient they are when the host app is backgrounded or terminated —
/// the mobile implementation uses URLSession (iOS) / WorkManager (Android)
/// via `flutter_downloader`, the fallback uses Dart's `http` client and
/// only runs while the isolate is alive.
abstract class BackgroundDownloader {
  /// Download [url] into `savedDir/filename`. Emits progress events as the
  /// transfer proceeds. The stream completes (without error) on success
  /// after the file is fully written, and emits an error if the transfer
  /// fails. Cancelling the stream subscription aborts the download.
  Stream<DownloadProgressEvent> download({
    required String url,
    required String savedDir,
    required String filename,
    Map<String, String> headers = const {},
  });

  /// Releases any long-lived resources (HTTP clients, isolate ports).
  /// Implementations should make this idempotent. The default is a no-op
  /// for downloaders that hold no persistent state outside an active
  /// transfer.
  void dispose() {}
}

/// Foreground-only downloader backed by Dart's `http` client. Used on
/// platforms where `flutter_downloader` isn't available (desktop, web,
/// tests). On iOS this will pause when the app is backgrounded, which is
/// why mobile builds prefer [FlutterBackgroundDownloader].
class HttpBackgroundDownloader implements BackgroundDownloader {
  HttpBackgroundDownloader({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  @override
  Stream<DownloadProgressEvent> download({
    required String url,
    required String savedDir,
    required String filename,
    Map<String, String> headers = const {},
  }) async* {
    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headers);
    final response = await _http.send(request);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw HttpException(
        'Server rejected the download (HTTP ${response.statusCode}). '
        'Check your access token and license acceptance.',
        uri: Uri.parse(url),
      );
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'Download failed: HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final target = File(p.join(savedDir, filename));
    if (await target.exists()) await target.delete();

    final total = response.contentLength;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgressEvent(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  void dispose() => _http.close();
}

/// Mobile downloader backed by `flutter_downloader`, which uses a
/// background `URLSession` on iOS and `WorkManager` on Android. Transfers
/// continue when the app is backgrounded or killed, which matters for the
/// ~3 GB Gemma model download.
///
/// Progress arrives as a percentage (0-100) over an [IsolateNameServer]
/// port; this class adapts that to a [DownloadProgressEvent] stream so
/// callers can stay agnostic of the implementation.
class FlutterBackgroundDownloader implements BackgroundDownloader {
  FlutterBackgroundDownloader();

  @override
  void dispose() {}

  /// Name used to register a [SendPort] for download progress callbacks.
  /// The static callback hops back into the UI isolate through this port.
  static const String _portName = 'bnpb_model_downloader_send_port';

  static Future<void>? _initFuture;

  /// Initialize the `flutter_downloader` plugin. Safe to call multiple
  /// times — the underlying call is idempotent and this method dedupes
  /// concurrent calls. Must be invoked from the main isolate after
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> ensureInitialized({bool debug = false}) {
    return _initFuture ??= FlutterDownloader.initialize(debug: debug);
  }

  @override
  Stream<DownloadProgressEvent> download({
    required String url,
    required String savedDir,
    required String filename,
    Map<String, String> headers = const {},
  }) {
    late final StreamController<DownloadProgressEvent> controller;
    String? taskId;
    ReceivePort? port;
    var portRegistered = false;
    var torndown = false;
    var reachedTerminalNatively = false;

    // Releases the [ReceivePort] and unregisters our send-port mapping.
    // If [cancelTask] is true (i.e. the consumer cancelled the
    // subscription while the download was still running), also asks
    // `flutter_downloader` to abort the native task. When the native side
    // already reported `complete`/`failed`/`canceled`, we skip the cancel
    // call — cancelling a finished task is at best a no-op and at worst
    // confuses the plugin's task table.
    Future<void> teardown({required bool cancelTask}) async {
      if (torndown) return;
      torndown = true;
      if (cancelTask && taskId != null && !reachedTerminalNatively) {
        try {
          await FlutterDownloader.cancel(taskId: taskId!);
        } catch (_) {}
      }
      port?.close();
      port = null;
      if (portRegistered) {
        IsolateNameServer.removePortNameMapping(_portName);
        portRegistered = false;
      }
    }

    controller = StreamController<DownloadProgressEvent>(
      onListen: () async {
        try {
          await ensureInitialized();
          // Clear any stale registration from a previous (cancelled) run
          // before re-registering our port.
          IsolateNameServer.removePortNameMapping(_portName);
          port = ReceivePort();
          IsolateNameServer.registerPortWithName(port!.sendPort, _portName);
          portRegistered = true;
          port!.listen((dynamic data) async {
            if (data is! List || data.length < 3) return;
            final id = data[0] as String;
            final statusInt = data[1] as int;
            final progress = data[2] as int;
            if (taskId == null || id != taskId) return;
            // flutter_downloader reports progress as 0-100. Surface that
            // as a fraction by emitting (progress, 100).
            if (!controller.isClosed) {
              controller.add(DownloadProgressEvent(progress, 100));
            }
            // Defensive bounds check: a future plugin version could
            // introduce a new status code we don't know about, which
            // would otherwise crash this isolate with a RangeError.
            final status =
                statusInt >= 0 && statusInt < DownloadTaskStatus.values.length
                    ? DownloadTaskStatus.values[statusInt]
                    : DownloadTaskStatus.undefined;
            if (status == DownloadTaskStatus.complete) {
              reachedTerminalNatively = true;
              await teardown(cancelTask: false);
              await controller.close();
            } else if (status == DownloadTaskStatus.failed) {
              reachedTerminalNatively = true;
              if (!controller.isClosed) {
                controller.addError(
                  StateError('Background download failed (task $id)'),
                );
              }
              await teardown(cancelTask: false);
              await controller.close();
            } else if (status == DownloadTaskStatus.canceled) {
              reachedTerminalNatively = true;
              await teardown(cancelTask: false);
              await controller.close();
            }
          });
          await FlutterDownloader.registerCallback(_downloadCallback);
          taskId = await FlutterDownloader.enqueue(
            url: url,
            headers: headers,
            savedDir: savedDir,
            fileName: filename,
            showNotification: true,
            openFileFromNotification: false,
            saveInPublicStorage: false,
          );
          if (taskId == null) {
            controller.addError(
              StateError('flutter_downloader returned a null task id'),
            );
            await teardown(cancelTask: false);
            await controller.close();
          }
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
          await teardown(cancelTask: true);
          if (!controller.isClosed) await controller.close();
        }
      },
      onCancel: () => teardown(cancelTask: true),
    );
    return controller.stream;
  }
}

/// Top-level callback invoked by `flutter_downloader` from its background
/// isolate. Forwards events to the UI isolate via the named send port.
@pragma('vm:entry-point')
void _downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName(
    FlutterBackgroundDownloader._portName,
  );
  send?.send([id, status, progress]);
}

/// Returns the platform-appropriate downloader. Mobile gets the
/// background-safe implementation; everywhere else falls back to the
/// foreground HTTP client.
BackgroundDownloader defaultBackgroundDownloader() {
  if (kIsWeb) return HttpBackgroundDownloader();
  if (Platform.isIOS || Platform.isAndroid) {
    return FlutterBackgroundDownloader();
  }
  return HttpBackgroundDownloader();
}
