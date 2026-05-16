import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ai/ai_feature_gate.dart';
import '../services/ai/ai_services.dart';
import '../services/ai/embedder_manager.dart';
import '../services/ai/hf_token_store.dart';
import '../services/ai/key_validation.dart';
import '../services/ai/model_manager.dart';
import '../services/security_service.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final ModelManager _modelManager = ModelManager();
  final EmbedderManager _embedderManager = EmbedderManager();
  final HfTokenStore _tokenStore = HfTokenStore();
  bool _enabled = false;
  ModelStatus _status = ModelStatus.absent;
  EmbedderStatus _embedderStatus = EmbedderStatus.absent;
  bool _hasToken = false;
  bool _loading = true;
  bool _busy = false;
  AiBackend _backend = AiBackend.local;
  bool _hasGeminiKey = false;
  double? _downloadProgress;
  double? _embedderDownloadProgress;
  StreamSubscription<ModelDownloadProgress>? _downloadSub;
  StreamSubscription<EmbedderDownloadProgress>? _embedderDownloadSub;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _embedderDownloadSub?.cancel();
    _modelManager.dispose();
    _embedderManager.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await AiServices().gate.isEnabled();
    final status = await _modelManager.status();
    final embedderStatus = await _embedderManager.status();
    final token = await _tokenStore.read();
    final backend = await AiServices().gate.backend();
    final hasGeminiKey = await SecurityService().hasGeminiApiKey();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _status = status;
      _embedderStatus = embedderStatus;
      _hasToken = token != null && token.isNotEmpty;
      _backend = backend;
      _hasGeminiKey = hasGeminiKey;
      _loading = false;
    });
  }

  Future<void> _promptForToken() async {
    final existing = await _tokenStore.read();
    if (!mounted) return;
    final result = await showDialog<_KeyDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KeyDialog(
        title: 'Hugging Face access token',
        explanation:
            'The Gemma model is gated by Google. Create a read-only token '
            'at huggingface.co/settings/tokens, accept the Gemma license on '
            'the model page, then paste the token below. It is stored in '
            'the device key store and only sent to huggingface.co.',
        fieldLabel: 'hf_…',
        initialValue: existing ?? '',
        validate: KeyValidator.huggingFace,
      ),
    );
    if (result == null) return;
    if (result.cleared) {
      await _tokenStore.delete();
    } else {
      await _tokenStore.write(result.value!);
    }
    if (!mounted) return;
    final msg = result.cleared
        ? 'Hugging Face token cleared'
        : result.validated
            ? 'Hugging Face token saved and validated'
            : 'Hugging Face token saved without validation';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _refresh();
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _busy = true);
    await AiServices().gate.setEnabled(value);
    if (value) {
      await AiServices().refreshBackend();
      // Loading the model file is only meaningful for the local backend.
      if (_backend == AiBackend.local && _status == ModelStatus.ready) {
        try {
          final path = await _modelManager.modelPath();
          await AiServices().llm.load(path);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not load model: $error')),
            );
          }
        }
      }
    } else {
      await AiServices().llm.unload();
    }
    if (!mounted) return;
    setState(() {
      _enabled = value;
      _busy = false;
    });
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _downloadProgress = 0;
    });
    try {
      final token = await _tokenStore.read();
      final stream = _modelManager.download(huggingFaceToken: token);
      _downloadSub = stream.listen(
        (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress.fraction);
        },
        onDone: () async {
          if (!mounted) return;
          setState(() {
            _downloadProgress = null;
            _busy = false;
          });
          await _refresh();
          if (_enabled) {
            try {
              final path = await _modelManager.modelPath();
              await AiServices().llm.load(path);
            } catch (_) {}
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = null;
            _busy = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $error')),
          );
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $error')),
      );
    }
  }

  Future<void> _cancelDownload() async {
    final sub = _downloadSub;
    if (sub == null) return;
    _downloadSub = null;
    await sub.cancel();
    await _modelManager.deletePartial();
    if (!mounted) return;
    setState(() {
      _downloadProgress = null;
      _busy = false;
    });
    await _refresh();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete AI model?'),
        content: const Text(
          'The model file will be removed from this device. AI features will '
          'be unavailable until you download it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await AiServices().llm.unload();
    await _modelManager.delete();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _downloadEmbedder() async {
    setState(() {
      _busy = true;
      _embedderDownloadProgress = 0;
    });
    try {
      final stream = _embedderManager.download();
      _embedderDownloadSub = stream.listen(
        (progress) {
          if (!mounted) return;
          setState(() => _embedderDownloadProgress = progress.fraction);
        },
        onDone: () async {
          if (!mounted) return;
          setState(() {
            _embedderDownloadProgress = null;
            _busy = false;
          });
          await _refresh();
          if (_enabled && _embedderStatus == EmbedderStatus.ready) {
            try {
              await AiServices().embedding.load(
                    modelPath: await _embedderManager.modelPath(),
                    tokenizerPath: await _embedderManager.tokenizerPath(),
                  );
            } catch (_) {}
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _embedderDownloadProgress = null;
            _busy = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Embedder download failed: $error')),
          );
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _embedderDownloadProgress = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Embedder download failed: $error')),
      );
    }
  }

  Future<void> _cancelEmbedderDownload() async {
    final sub = _embedderDownloadSub;
    if (sub == null) return;
    _embedderDownloadSub = null;
    await sub.cancel();
    await _embedderManager.deletePartial();
    if (!mounted) return;
    setState(() {
      _embedderDownloadProgress = null;
      _busy = false;
    });
    await _refresh();
  }

  Future<void> _deleteEmbedder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete embedder?'),
        content: const Text(
          'The embedder model and tokenizer will be removed from this device. '
          'Ask search will be unavailable until you download them again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await AiServices().embedding.unload();
    await AiServices().semanticSearch.clear();
    await _embedderManager.delete();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _showCloudDisclosure() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Switch AI to Google Gemini?',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Text(
                          'By default, BNPB runs every AI feature on this '
                          'device and no note text ever leaves it.\n\n'
                          'If you turn on cloud AI, the following changes:\n\n'
                          '•  The text you ask the AI to process — '
                          'interaction notes, prayer requests, summaries — '
                          'will be sent over HTTPS to '
                          'generativelanguage.googleapis.com (Google '
                          'Gemini) using your own API key.\n\n'
                          '•  That data is governed by Google\'s API terms '
                          'of service and privacy policy, not just '
                          'BNPB\'s.\n\n'
                          '•  Your Google AI Studio API key is stored in '
                          'this device\'s secure key store (Keychain / '
                          'Keystore) and is only sent in the Authorization '
                          'header to Google.\n\n'
                          '•  AI features that depend on the network will '
                          'fail with a visible error when offline. BNPB '
                          'will not silently fall back to the on-device '
                          'model — that would obscure which backend '
                          'produced the result.\n\n'
                          'You can switch back to on-device AI at any time, '
                          'and removing the API key disables the cloud path '
                          'immediately.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Keep on-device'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Use cloud AI'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _promptForGeminiApiKey() async {
    final existing = await SecurityService().getGeminiApiKey();
    if (!mounted) return;
    final result = await showDialog<_KeyDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KeyDialog(
        title: 'Google Gemini API key',
        explanation:
            'Create a free key at aistudio.google.com/app/apikey and paste '
            'it here. The key is stored in this device\'s secure key store '
            'and only sent to Google in the Authorization header. Leave '
            'blank to clear.',
        fieldLabel: 'AIza…',
        initialValue: existing ?? '',
        validate: KeyValidator.gemini,
      ),
    );
    if (result == null) return;
    await SecurityService()
        .setGeminiApiKey(result.cleared ? null : result.value);
    await AiServices().refreshBackend();
    if (!mounted) return;
    final msg = result.cleared
        ? 'Gemini API key cleared'
        : result.validated
            ? 'Gemini API key saved and validated'
            : 'Gemini API key saved without validation';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _refresh();
  }

  Future<void> _setBackend(bool useCloud) async {
    if (useCloud == (_backend == AiBackend.cloud)) return;

    if (useCloud) {
      // Disclosure must happen BEFORE the optimistic flip — the toggle
      // represents consent and we can't grant it on the user's behalf.
      final confirmed = await _showCloudDisclosure();
      if (!confirmed) return;
      // Optimistic: user has confirmed consent, so flip the toggle now
      // and persist + maybe prompt for a key in the background. If they
      // back out of the key prompt, the toggle stays on with the
      // "no API key set" subtitle and a tap on the API key tile finishes
      // the setup.
      setState(() => _backend = AiBackend.cloud);
      unawaited(_applyCloudBackend());
    } else {
      // Optimistic flip — turning cloud off doesn't need confirmation.
      setState(() => _backend = AiBackend.local);
      unawaited(_applyLocalBackend());
    }
  }

  Future<void> _applyCloudBackend() async {
    await AiServices().gate.setBackend(AiBackend.cloud);
    if (!await SecurityService().hasGeminiApiKey()) {
      if (mounted) await _promptForGeminiApiKey();
    } else {
      await AiServices().refreshBackend();
    }
    if (mounted) await _refresh();
  }

  Future<void> _applyLocalBackend() async {
    await AiServices().gate.setBackend(AiBackend.local);
    await AiServices().refreshBackend();
    // If AI is enabled and the on-device model is on disk, load it so the
    // user can use AI immediately after switching back.
    if (_enabled && _status == ModelStatus.ready) {
      try {
        final path = await _modelManager.modelPath();
        await AiServices().llm.load(path);
      } catch (_) {}
    }
    if (mounted) await _refresh();
  }

  String _embedderStatusLabel() {
    switch (_embedderStatus) {
      case EmbedderStatus.absent:
        return 'Not installed';
      case EmbedderStatus.partial:
        return 'Incomplete — re-download required';
      case EmbedderStatus.ready:
        return 'Ready on device';
      case EmbedderStatus.corrupt:
        return 'Corrupt — re-download required';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI features')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'AI suggestions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'BNPB can suggest follow-up actions and tags after you '
                    'log an interaction. AI is off until you turn it on, and '
                    'runs entirely on this device unless you explicitly '
                    'switch the backend to Google Gemini in the Backend '
                    'section below.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SwitchListTile.adaptive(
                  title: const Text('Enable AI features'),
                  subtitle: Text(_enabled
                      ? _backend == AiBackend.cloud
                          ? _hasGeminiKey
                              ? 'On — using Google Gemini (cloud)'
                              : 'On — cloud selected, no API key set'
                          : _status == ModelStatus.ready
                              ? 'On — using on-device model'
                              : 'On — model not downloaded'
                      : 'Off'),
                  value: _enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),

                const Divider(),

                // ── Backend section ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Backend',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'On-device keeps every prompt and result on this phone. '
                    'Cloud sends note text to Google Gemini for faster and '
                    'higher-quality suggestions; you supply your own API key '
                    'and accept that the text leaves your device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.cloud_outlined),
                  title: const Text('Use Google Gemini (cloud)'),
                  subtitle: Text(_backend == AiBackend.cloud
                      ? _hasGeminiKey
                          ? 'On — note text is sent to Google'
                          : 'On — add an API key below'
                      : 'Off — AI runs entirely on this device'),
                  value: _backend == AiBackend.cloud,
                  onChanged: _busy ? null : _setBackend,
                ),
                if (_backend == AiBackend.cloud)
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Gemini API key'),
                    subtitle: Text(
                      _hasGeminiKey
                          ? 'Saved in this device\'s key store — tap to update or clear'
                          : 'Required. Get a free key at aistudio.google.com/app/apikey',
                    ),
                    enabled: !_busy,
                    onTap: _busy ? null : _promptForGeminiApiKey,
                  ),

                const Divider(),

                // ── On-device model section ────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'On-device model',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    _backend == AiBackend.cloud
                        ? 'Used when the backend above is set back to '
                            'on-device. The Gemma model file (~3.1 GB) can '
                            'stay on disk as a fallback or be deleted to '
                            'free space.'
                        : 'The Gemma model (~3.1 GB) is downloaded from '
                            'Hugging Face. A read-only access token is '
                            'required because the repository is gated by '
                            'Google.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: const Text('Hugging Face token'),
                  subtitle: Text(
                    _hasToken
                        ? 'Saved — tap to update'
                        : 'Required to download the gated Gemma model',
                  ),
                  enabled: !_busy,
                  onTap: _busy ? null : _promptForToken,
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(_status == ModelStatus.ready
                      ? 'Re-download model'
                      : 'Download model'),
                  subtitle: Text(_hasToken
                      ? _statusLabel()
                      : 'Add a Hugging Face token first'),
                  enabled: !_busy && _hasToken,
                  onTap: _busy || !_hasToken ? null : _download,
                ),
                if (_downloadProgress != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _cancelDownload,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete model'),
                  subtitle: const Text('Frees device storage'),
                  enabled: !_busy && _status != ModelStatus.absent,
                  onTap:
                      _busy || _status == ModelStatus.absent ? null : _delete,
                ),

                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Ask search (semantic)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Enables the "Ask" toggle on the search bar so you can '
                    'ask questions like "who did I last pray for about job '
                    'hunting?". Uses a small (~110 MB) Gecko embedder that '
                    'runs entirely on this device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.psychology_outlined),
                  title: Text(_embedderStatus == EmbedderStatus.ready
                      ? 'Re-download embedder'
                      : 'Download embedder'),
                  subtitle: Text(_embedderStatusLabel()),
                  enabled: !_busy,
                  onTap: _busy ? null : _downloadEmbedder,
                ),
                if (_embedderDownloadProgress != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _embedderDownloadProgress,
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _cancelEmbedderDownload,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete embedder'),
                  subtitle: const Text('Frees device storage'),
                  enabled: !_busy && _embedderStatus != EmbedderStatus.absent,
                  onTap: _busy || _embedderStatus == EmbedderStatus.absent
                      ? null
                      : _deleteEmbedder,
                ),
              ],
            ),
    );
  }

  String _statusLabel() {
    switch (_status) {
      case ModelStatus.absent:
        return 'Not downloaded';
      case ModelStatus.downloading:
        return 'Downloading…';
      case ModelStatus.ready:
        return 'Ready on device';
      case ModelStatus.corrupt:
        return 'Corrupt — re-download required';
    }
  }
}

/// Result of a key/token entry flow.
///
/// `null` Dialog result = user cancelled (caller does nothing).
/// `cleared = true` = user left the field empty and confirmed (clear the
/// stored value).
/// Otherwise [value] is the trimmed credential to store; [validated]
/// tells the caller whether the remote service accepted it, so a
/// "saved without validation" snackbar can call that out.
class _KeyDialogResult {
  const _KeyDialogResult.saved(this.value, {required this.validated})
      : cleared = false;
  const _KeyDialogResult.cleared()
      : value = null,
        cleared = true,
        validated = false;

  final String? value;
  final bool cleared;
  final bool validated;
}

/// Generic credential-entry dialog that runs a health-check validator
/// before letting the user save. Used for both the Hugging Face token
/// and the Gemini API key — they have the same shape (paste, validate,
/// either succeed or show inline error). Network-error states offer a
/// "Save anyway" path so an offline user isn't locked out.
class _KeyDialog extends StatefulWidget {
  const _KeyDialog({
    required this.title,
    required this.explanation,
    required this.fieldLabel,
    required this.initialValue,
    required this.validate,
  });

  final String title;
  final String explanation;
  final String fieldLabel;
  final String initialValue;
  final Future<KeyValidationResult> Function(String value) validate;

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  bool _checking = false;
  String? _errorText;
  // Last network-error result. When non-null, we render a "Save anyway"
  // affordance instead of plain Save.
  KeyValidationResult? _networkError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop(const _KeyDialogResult.cleared());
      return;
    }
    setState(() {
      _checking = true;
      _errorText = null;
      _networkError = null;
    });
    final result = await widget.validate(value);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(
        _KeyDialogResult.saved(value, validated: true),
      );
      return;
    }
    setState(() {
      _checking = false;
      _errorText = result.message;
      _networkError = result.networkError ? result : null;
    });
  }

  void _onSaveAnyway() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(
      _KeyDialogResult.saved(value, validated: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.explanation),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            enabled: !_checking,
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              border: const OutlineInputBorder(),
              errorText: _errorText,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        if (_networkError != null)
          TextButton(
            onPressed: _checking ? null : _onSaveAnyway,
            child: const Text('Save anyway'),
          ),
        TextButton(
          onPressed: _checking ? null : _onSave,
          child: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_networkError != null ? 'Retry' : 'Save'),
        ),
      ],
    );
  }
}
