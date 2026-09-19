// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show CrispColorScheme;
import '../services/ai/ai_feature_gate.dart';
import '../services/ai/ai_services.dart';
import '../services/ai/dynamic_model_catalog.dart';
import '../services/ai/embedder_manager.dart';
import '../services/ai/hf_token_store.dart';
import '../services/ai/key_validation.dart';
import '../services/ai/local_llm_service.dart';
import '../services/ai/model_manager.dart';
import '../services/security_service.dart';
import '../widgets/crisp_toast.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  ModelManager? _modelManager;
  final EmbedderManager _embedderManager = EmbedderManager();
  final HfTokenStore _tokenStore = HfTokenStore();
  bool _enabled = false;
  bool _showSuggestionsOnSave = false;
  bool _scriptureRefAdvancement = false;
  ModelStatus _status = ModelStatus.absent;
  EmbedderStatus _embedderStatus = EmbedderStatus.absent;
  bool _hasToken = false;
  bool _loading = true;
  bool _busy = false;
  AiBackend _backend = AiBackend.local;
  bool _hasGeminiKey = false;
  bool _hasClaudeKey = false;
  String _selectedModel = '';
  List<AiModelInfo> _availableModels = [];
  bool _loadingModels = false;
  String _selectedLocalModelId = OnDeviceModelSpec.supportedModels.first.id;
  double? _downloadProgress;
  double? _embedderDownloadProgress;
  StreamSubscription<ModelDownloadProgress>? _downloadSub;
  StreamSubscription<EmbedderDownloadProgress>? _embedderDownloadSub;

  ModelManager get _activeModelManager {
    final spec = OnDeviceModelSpec.forId(_selectedLocalModelId);
    return _modelManager ??= ModelManager(modelSpec: spec);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _embedderDownloadSub?.cancel();
    _modelManager?.dispose();
    _embedderManager.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await AiServices().gate.isEnabled();
    final showSuggestionsOnSave =
        await AiServices().gate.isShowSuggestionsOnSaveEnabled();
    final scriptureRefAdvancement =
        await AiServices().gate.isScriptureRefAdvancementEnabled();
    final backend = await AiServices().gate.backend();
    final selectedLocalId =
        await AiServices().gate.getSelectedModel(AiBackend.local);
    _selectedLocalModelId = selectedLocalId;

    _modelManager?.dispose();
    final spec = OnDeviceModelSpec.forId(selectedLocalId);
    _modelManager = ModelManager(modelSpec: spec);

    final status = await _modelManager!.status();
    final embedderStatus = await _embedderManager.status();
    final token = await _tokenStore.read();
    final hasGeminiKey = await SecurityService().hasGeminiApiKey();
    final hasClaudeKey = await SecurityService().hasAnthropicApiKey();
    final selectedModel = await AiServices().gate.getSelectedModel(backend);

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _showSuggestionsOnSave = showSuggestionsOnSave;
      _scriptureRefAdvancement = scriptureRefAdvancement;
      _status = status;
      _embedderStatus = embedderStatus;
      _hasToken = token != null && token.isNotEmpty;
      _backend = backend;
      _hasGeminiKey = hasGeminiKey;
      _hasClaudeKey = hasClaudeKey;
      _selectedModel = selectedModel;
      _loading = false;
    });

    _loadModels(backend);
  }

  Future<void> _loadModels(AiBackend backend) async {
    if (!mounted) return;
    setState(() => _loadingModels = true);
    String? key;
    if (backend == AiBackend.cloud) {
      key = await SecurityService().getGeminiApiKey();
    } else if (backend == AiBackend.claude) {
      key = await SecurityService().getAnthropicApiKey();
    }

    final models = await DynamicModelCatalog().getModels(backend, apiKey: key);
    if (!mounted) return;
    setState(() {
      _availableModels = models;
      _loadingModels = false;
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
            'Gated models require an access token. Create a read-only token '
            'at huggingface.co/settings/tokens, accept the model license if required, '
            'then paste the token below. It is stored securely on device and '
            'only used to download model files. All AI inference runs 100% offline.',
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
    CrispToast.show(context, msg);
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
          await _loadLocalModel();
        } catch (error) {
          if (mounted) {
            CrispToast.show(context, 'Could not load model: $error');
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

  Future<void> _setShowSuggestionsOnSave(bool value) async {
    setState(() => _busy = true);
    await AiServices().gate.setShowSuggestionsOnSaveEnabled(value);
    if (!mounted) return;
    setState(() {
      _showSuggestionsOnSave = value;
      _busy = false;
    });
  }

  Future<void> _setScriptureRefAdvancement(bool value) async {
    setState(() => _busy = true);
    await AiServices().gate.setScriptureRefAdvancementEnabled(value);
    if (!mounted) return;
    setState(() {
      _scriptureRefAdvancement = value;
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
      final stream = _activeModelManager.download(huggingFaceToken: token);
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
              await _loadLocalModel();
            } catch (_) {}
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = null;
            _busy = false;
          });
          CrispToast.show(context, 'Download failed: $error');
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = null;
        _busy = false;
      });
      CrispToast.show(context, 'Download failed: $error');
    }
  }

  Future<void> _cancelDownload() async {
    final sub = _downloadSub;
    if (sub == null) return;
    _downloadSub = null;
    await sub.cancel();
    await _activeModelManager.deletePartial();
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
    await _activeModelManager.delete();
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
          CrispToast.show(context, 'Embedder download failed: $error');
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _embedderDownloadProgress = null;
        _busy = false;
      });
      CrispToast.show(context, 'Embedder download failed: $error');
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

  Future<bool> _showCloudDisclosure(AiBackend backend) async {
    final isClaude = backend == AiBackend.claude;
    final providerName = isClaude ? 'Anthropic Claude' : 'Google Gemini';
    final endpoint = isClaude
        ? 'api.anthropic.com (Anthropic Claude)'
        : 'generativelanguage.googleapis.com (Google Gemini)';
    final keyStore =
        isClaude ? 'Anthropic API key' : 'Google AI Studio API key';
    final termsAuthority = isClaude
        ? "Anthropic's Commercial Terms and privacy policy"
        : "Google's API terms of service and privacy policy";

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
                        'Switch AI to $providerName?',
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
                          '$endpoint using your own API key.\n\n'
                          '•  That data is governed by $termsAuthority, not just '
                          'BNPB\'s.\n\n'
                          '•  Your $keyStore is stored in '
                          'this device\'s secure key store (Keychain / '
                          'Keystore) and is only sent in headers to $providerName.\n\n'
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
    await SecurityService().setGeminiApiKey(
      result.cleared ? null : result.value,
    );
    await AiServices().refreshBackend();
    if (!mounted) return;
    final msg = result.cleared
        ? 'Gemini API key cleared'
        : result.validated
            ? 'Gemini API key saved and validated'
            : 'Gemini API key saved without validation';
    CrispToast.show(context, msg);
    await _refresh();
  }

  Future<void> _promptForClaudeApiKey() async {
    final existing = await SecurityService().getAnthropicApiKey();
    if (!mounted) return;
    final result = await showDialog<_KeyDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KeyDialog(
        title: 'Anthropic (Claude) API key',
        explanation: 'Create a key at console.anthropic.com and paste '
            'it here. The key is stored in this device\'s secure key store '
            'and only sent to Anthropic in the x-api-key header. Leave '
            'blank to clear.',
        fieldLabel: 'sk-ant-…',
        initialValue: existing ?? '',
        validate: KeyValidator.claude,
      ),
    );
    if (result == null) return;
    await SecurityService().setAnthropicApiKey(
      result.cleared ? null : result.value,
    );
    await AiServices().refreshBackend();
    if (!mounted) return;
    final msg = result.cleared
        ? 'Claude API key cleared'
        : result.validated
            ? 'Claude API key saved and validated'
            : 'Claude API key saved without validation';
    CrispToast.show(context, msg);
    await _refresh();
  }

  Future<void> _onModelSelected(String modelId) async {
    await AiServices().gate.setSelectedModel(_backend, modelId);
    await AiServices().refreshBackend();
    if (mounted) {
      setState(() => _selectedModel = modelId);
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
        await _loadLocalModel();
      } catch (_) {}
    }
    if (mounted) await _refresh();
  }

  Future<void> _loadLocalModel([String? modelId]) async {
    final spec = OnDeviceModelSpec.forId(modelId ?? _selectedLocalModelId);
    final manager = ModelManager(modelSpec: spec);
    final path = await manager.modelPath();
    final llm = AiServices().llm;
    if (llm is FlutterGemmaLlmService) {
      await llm.load(path, spec.modelType);
    } else {
      await llm.load(path);
    }
    manager.dispose();
  }

  Future<void> _onLocalModelSelected(String modelId) async {
    await AiServices().gate.setSelectedModel(AiBackend.local, modelId);
    await AiServices().llm.unload();
    await _refresh();
    if (_enabled && _status == ModelStatus.ready) {
      try {
        await _loadLocalModel(modelId);
      } catch (_) {}
    }
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
    return HideOnScrollScaffold(
      appBar: AppBar(title: const Text('AI features')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                  child: Text(
                    'AI suggestions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                  child: Text(
                    'BNPB can suggest follow-up actions and tags after you '
                    'log an interaction. AI is off until you turn it on, and '
                    'runs entirely on this device unless you explicitly '
                    'switch the backend to a cloud provider in the Backend '
                    'section below.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondaryText,
                        ),
                  ),
                ),
                _buildCardGroup(
                  children: [
                    SwitchListTile.adaptive(
                      title: const Text('Enable AI features'),
                      subtitle: Text(
                        _enabled
                            ? _backend == AiBackend.cloud
                                ? _hasGeminiKey
                                    ? 'On — using Google Gemini (cloud)'
                                    : 'On — Gemini selected, no API key set'
                                : _backend == AiBackend.claude
                                    ? _hasClaudeKey
                                        ? 'On — using Anthropic Claude (cloud)'
                                        : 'On — Claude selected, no API key set'
                                    : _status == ModelStatus.ready
                                        ? 'On — using on-device model'
                                        : 'On — model not downloaded'
                            : 'Off',
                      ),
                      value: _enabled,
                      onChanged: _busy ? null : _setEnabled,
                    ),
                    if (_enabled) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile.adaptive(
                        title: const Text('Show suggestions when saving'),
                        subtitle: const Text(
                          'Generate follow-up reminders automatically after logging an interaction',
                        ),
                        value: _showSuggestionsOnSave,
                        onChanged: _busy ? null : _setShowSuggestionsOnSave,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile.adaptive(
                        title: const Text(
                          'Use AI for Ready-to-log suggestions',
                        ),
                        subtitle: const Text(
                          'When a scripture reference is written in free form '
                          '(e.g. "Psalm one-seventeen"), ask the on-device model '
                          'to suggest the next passage',
                        ),
                        value: _scriptureRefAdvancement,
                        onChanged: _busy ? null : _setScriptureRefAdvancement,
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // ── Backend section ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                  child: Text(
                    'Backend',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                  child: Text(
                    'On-device keeps every prompt and result strictly on this phone. '
                    'Cloud backends (Google Gemini or Anthropic Claude) offer faster responses '
                    'and higher intelligence; you supply your own API key and accept that '
                    'the prompt text leaves your device.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondaryText,
                        ),
                  ),
                ),
                _buildCardGroup(
                  children: [
                    RadioListTile<AiBackend>(
                      title: const Text('On-device (Private)'),
                      subtitle: Text(
                        '${OnDeviceModelSpec.forId(_selectedLocalModelId).displayName} — runs locally, zero data leaves device',
                      ),
                      value: AiBackend.local,
                      groupValue: _backend,
                      onChanged: _busy
                          ? null
                          : (val) async {
                              if (val == null) return;
                              setState(() => _backend = val);
                              await _applyLocalBackend();
                            },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    RadioListTile<AiBackend>(
                      title: const Text('Google Gemini (Cloud)'),
                      subtitle: Text(_hasGeminiKey
                          ? 'API key configured'
                          : 'API key required'),
                      value: AiBackend.cloud,
                      groupValue: _backend,
                      onChanged: _busy
                          ? null
                          : (val) async {
                              if (val == null) return;
                              final confirmed = await _showCloudDisclosure(val);
                              if (!confirmed) return;
                              setState(() => _backend = val);
                              await _applyCloudBackend();
                            },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    RadioListTile<AiBackend>(
                      title: const Text('Anthropic Claude (Cloud)'),
                      subtitle: Text(_hasClaudeKey
                          ? 'API key configured'
                          : 'API key required'),
                      value: AiBackend.claude,
                      groupValue: _backend,
                      onChanged: _busy
                          ? null
                          : (val) async {
                              if (val == null) return;
                              final confirmed = await _showCloudDisclosure(val);
                              if (!confirmed) return;
                              setState(() => _backend = val);
                              await AiServices().gate.setBackend(val);
                              if (!await SecurityService()
                                  .hasAnthropicApiKey()) {
                                if (mounted) await _promptForClaudeApiKey();
                              } else {
                                await AiServices().refreshBackend();
                              }
                              if (mounted) await _refresh();
                            },
                    ),
                    if (_backend == AiBackend.cloud) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: const Text('Gemini API key'),
                        subtitle: Text(
                          _hasGeminiKey
                              ? 'Saved in key store — tap to update or clear'
                              : 'Required. Get a key at aistudio.google.com/app/apikey',
                        ),
                        enabled: !_busy,
                        onTap: _busy ? null : _promptForGeminiApiKey,
                      ),
                    ],
                    if (_backend == AiBackend.claude) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: const Text('Anthropic API key'),
                        subtitle: Text(
                          _hasClaudeKey
                              ? 'Saved in key store — tap to update or clear'
                              : 'Required. Get a key at console.anthropic.com',
                        ),
                        enabled: !_busy,
                        onTap: _busy ? null : _promptForClaudeApiKey,
                      ),
                    ],
                    if (_backend != AiBackend.local) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Model Selection & Pricing',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                if (_loadingModels)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 18),
                                    tooltip: 'Refresh model catalog',
                                    onPressed: () => _loadModels(_backend),
                                  ),
                              ],
                            ),
                            if (_availableModels.isNotEmpty)
                              DropdownButtonFormField<String>(
                                value: _availableModels
                                        .any((m) => m.id == _selectedModel)
                                    ? _selectedModel
                                    : _availableModels.first.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                items: _availableModels.map((model) {
                                  return DropdownMenuItem<String>(
                                    value: model.id,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          model.displayName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13),
                                        ),
                                        Text(
                                          model.pricingLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) _onModelSelected(val);
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // ── On-device model section ────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                  child: Text(
                    'On-device model',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                  child: Text(
                    'Select an offline model to run locally on this phone. '
                    'Models are downloaded directly from Hugging Face into device storage. '
                    'Inference runs 100% offline with zero external network calls.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondaryText,
                        ),
                  ),
                ),
                _buildCardGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Active On-Device Model',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedLocalModelId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items:
                                OnDeviceModelSpec.supportedModels.map((spec) {
                              return DropdownMenuItem<String>(
                                value: spec.id,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${spec.displayName} (${spec.sizeLabel})',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      spec.description,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: _busy
                                ? null
                                : (val) {
                                    if (val != null) _onLocalModelSelected(val);
                                  },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    if (_status == ModelStatus.ready) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Theme.of(context).colorScheme.greenTint,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${OnDeviceModelSpec.forId(_selectedLocalModelId).displayName} ready',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'Ready for offline AI suggestions on this device.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: const Text('Hugging Face token'),
                      subtitle: Text(
                        _hasToken
                            ? 'Saved — tap to update'
                            : 'Required to download gated models from Hugging Face',
                      ),
                      enabled: !_busy,
                      onTap: _busy ? null : _promptForToken,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: Text(
                        _status == ModelStatus.ready
                            ? 'Re-download model'
                            : 'Download model',
                      ),
                      subtitle: Text(
                        _hasToken
                            ? _statusLabel()
                            : 'Add a Hugging Face token first',
                      ),
                      enabled: !_busy && _hasToken,
                      onTap: _busy || !_hasToken ? null : _download,
                    ),
                    if (_downloadProgress != null) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
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
                    ],
                    if (_status != ModelStatus.absent) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Delete model'),
                        subtitle: const Text('Frees device storage'),
                        enabled: !_busy && _status != ModelStatus.absent,
                        onTap: _busy || _status == ModelStatus.absent
                            ? null
                            : _delete,
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // ── Ask search (semantic) ──────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                  child: Text(
                    'Ask search (semantic)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                  child: Text(
                    'Enables the "Ask" toggle on the search bar so you can '
                    'ask questions like "who did I last pray for about job '
                    'hunting?". Uses a small (~110 MB) Gecko embedder that '
                    'runs entirely on this device.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondaryText,
                        ),
                  ),
                ),
                _buildCardGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.psychology_outlined),
                      title: Text(
                        _embedderStatus == EmbedderStatus.ready
                            ? 'Re-download embedder'
                            : 'Download embedder',
                      ),
                      subtitle: Text(_embedderStatusLabel()),
                      enabled: !_busy,
                      onTap: _busy ? null : _downloadEmbedder,
                    ),
                    if (_embedderDownloadProgress != null) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
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
                    ],
                    if (_embedderStatus != EmbedderStatus.absent) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Delete embedder'),
                        subtitle: const Text('Frees device storage'),
                        enabled:
                            !_busy && _embedderStatus != EmbedderStatus.absent,
                        onTap: _busy || _embedderStatus == EmbedderStatus.absent
                            ? null
                            : _deleteEmbedder,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildCardGroup({required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.cardBorder,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
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
      Navigator.of(context).pop(_KeyDialogResult.saved(value, validated: true));
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
    Navigator.of(context).pop(_KeyDialogResult.saved(value, validated: false));
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
