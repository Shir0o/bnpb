import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ai/ai_services.dart';
import '../services/ai/hf_token_store.dart';
import '../services/ai/model_manager.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final ModelManager _modelManager = ModelManager();
  final HfTokenStore _tokenStore = HfTokenStore();
  bool _enabled = false;
  ModelStatus _status = ModelStatus.absent;
  bool _hasToken = false;
  bool _loading = true;
  bool _busy = false;
  double? _downloadProgress;
  StreamSubscription<ModelDownloadProgress>? _downloadSub;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _modelManager.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await AiServices().gate.isEnabled();
    final status = await _modelManager.status();
    final token = await _tokenStore.read();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _status = status;
      _hasToken = token != null && token.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _promptForToken() async {
    final existing = await _tokenStore.read();
    if (!mounted) return;
    final controller = TextEditingController(text: existing);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hugging Face access token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Gemma model is gated by Google. Create a read-only token '
              'at huggingface.co/settings/tokens, accept the Gemma license '
              'on the model page, then paste the token below. It is stored '
              'in the device key store and only sent to huggingface.co.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'hf_…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      await _tokenStore.delete();
    } else {
      await _tokenStore.write(result);
    }
    await _refresh();
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _busy = true);
    await AiServices().gate.setEnabled(value);
    if (value && _status == ModelStatus.ready) {
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
    } else if (!value) {
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
                    'On-device AI suggestions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'BNPB can suggest follow-up actions and tags after you '
                    'log an interaction. All inference happens on this device '
                    'using a Gemma model that you download below (~3.1 GB). '
                    'No data leaves your device.',
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
                SwitchListTile.adaptive(
                  title: const Text('Enable AI features'),
                  subtitle: Text(_enabled
                      ? _status == ModelStatus.ready
                          ? 'On — model loaded'
                          : 'On — model not downloaded'
                      : 'Off'),
                  value: _enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),
                const Divider(),
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
