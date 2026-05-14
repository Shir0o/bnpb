import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Microphone button for the interaction editor. Press to start
/// recording, press again to stop. Live partial transcripts are
/// shown inline, and the final transcript is appended to the
/// supplied [controller] when listening stops.
///
/// Implementation choice for #172: on-device platform STT
/// (`speech_to_text` package, which delegates to Android's
/// SpeechRecognizer and iOS's SFSpeechRecognizer). Picked over a
/// cloud service to avoid adding a new network egress; the only
/// new privacy surface is the existing platform speech recognizer.
class VoiceToNoteButton extends StatefulWidget {
  const VoiceToNoteButton({
    super.key,
    required this.controller,
  });

  final TextEditingController controller;

  @override
  State<VoiceToNoteButton> createState() => _VoiceToNoteButtonState();
}

class _VoiceToNoteButtonState extends State<VoiceToNoteButton> {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _listening = false;
  String _partial = '';
  String? _errorMessage;

  // Only Android and iOS ship a reliable platform STT for this package.
  // Web and desktop fall through to the no-op render so we don't show a
  // button that would throw on tap.
  bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    if (_listening) {
      // Fire-and-forget — the widget is going away.
      unawaited(_stt.stop());
    }
    super.dispose();
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    final ok = await _stt.initialize(
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = err.errorMsg;
          _listening = false;
        });
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          setState(() => _listening = false);
        }
      },
    );
    if (!mounted) return ok;
    setState(() {
      _initialized = ok;
      if (!ok) {
        _errorMessage =
            'Microphone or speech recognition permission was denied.';
      }
    });
    return ok;
  }

  Future<void> _start() async {
    final ready = await _ensureInitialized();
    if (!ready || !mounted) return;
    setState(() {
      _partial = '';
      _errorMessage = null;
      _listening = true;
    });
    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          _appendToNotes(result.recognizedWords);
          // Clear so _stop() doesn't append the same text a second time.
          setState(() => _partial = '');
        } else {
          setState(() => _partial = result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> _stop() async {
    await _stt.stop();
    if (!mounted) return;
    // Some platforms don't deliver a final result if the user taps stop
    // before the recognizer settles. Persist whatever partial we have.
    if (_partial.trim().isNotEmpty) {
      _appendToNotes(_partial);
    }
    setState(() {
      _listening = false;
      _partial = '';
    });
  }

  void _appendToNotes(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return;
    final current = widget.controller.text;
    final separator = current.isEmpty
        ? ''
        : current.endsWith('\n')
            ? ''
            : '\n';
    widget.controller.text = '$current$separator$trimmed';
  }

  @override
  Widget build(BuildContext context) {
    if (!_platformSupported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _listening ? _stop : _start,
            icon: Icon(
              _listening ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
              size: 18,
              color: _listening ? theme.colorScheme.error : null,
            ),
            label: Text(_listening ? 'Stop dictation' : 'Dictate note'),
          ),
        ),
        if (_listening && _partial.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
            child: Text(
              _partial,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
            child: Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
