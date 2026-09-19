import 'package:shared_preferences/shared_preferences.dart';

/// Which AI backend is active when the feature gate is enabled.
///
/// [local] is on-device Gemma / LiteRT.
/// [cloud] is Google's Gemini API.
/// [claude] is Anthropic's Claude API.
/// [huggingface] is Hugging Face Serverless Inference API.
enum AiBackend { local, cloud, claude, huggingface }

/// User-controlled opt-in flag for AI features and the backend that
/// services them.
class AiFeatureGate {
  AiFeatureGate();

  static const String _enabledKey = 'ai.features.enabled';
  static const String _backendKey = 'ai.features.backend';
  static const String _backendCloud = 'cloud';
  static const String _backendLocal = 'local';
  static const String _backendClaude = 'claude';
  static const String _backendHf = 'huggingface';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static const String _showSuggestionsOnSaveKey =
      'ai.features.show_suggestions_on_save';

  static const String _scriptureRefAdvancementKey =
      'ai.features.scripture_ref_advancement';
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Returns the configured backend. Defaults to [AiBackend.local].
  Future<AiBackend> backend() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backendKey);
    switch (raw) {
      case _backendCloud:
        return AiBackend.cloud;
      case _backendClaude:
        return AiBackend.claude;
      case _backendHf:
        return AiBackend.huggingface;
      default:
        return AiBackend.local;
    }
  }

  Future<void> setBackend(AiBackend value) async {
    final prefs = await SharedPreferences.getInstance();
    String raw;
    switch (value) {
      case AiBackend.cloud:
        raw = _backendCloud;
        break;
      case AiBackend.claude:
        raw = _backendClaude;
        break;
      case AiBackend.huggingface:
        raw = _backendHf;
        break;
      case AiBackend.local:
        raw = _backendLocal;
        break;
    }
    await prefs.setString(_backendKey, raw);
  }

  /// Returns the selected model ID for a given backend, falling back to its default.
  Future<String> getSelectedModel(AiBackend backend) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai.provider.${backend.name}.model';
    final saved = prefs.getString(key);
    if (saved != null && saved.isNotEmpty) return saved;

    switch (backend) {
      case AiBackend.cloud:
        return 'gemini-2.5-flash';
      case AiBackend.claude:
        return 'claude-3-5-haiku-latest';
      case AiBackend.huggingface:
        return 'meta-llama/Llama-3.2-3B-Instruct';
      case AiBackend.local:
        return 'gemma-3n-e2b-int4';
    }
  }

  /// Sets the selected model ID for a given backend.
  Future<void> setSelectedModel(AiBackend backend, String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai.provider.${backend.name}.model';
    await prefs.setString(key, modelId.trim());
  }

  Future<bool> isShowSuggestionsOnSaveEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showSuggestionsOnSaveKey) ?? false;
  }

  Future<void> setShowSuggestionsOnSaveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showSuggestionsOnSaveKey, value);
  }

  /// Whether the Ready-to-log card should consult the on-device LLM for
  /// scripture refs that the regex path can't parse. Defaults to false
  /// (off) — AI is opt-in per feature, mirroring
  /// [isShowSuggestionsOnSaveEnabled].
  Future<bool> isScriptureRefAdvancementEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scriptureRefAdvancementKey) ?? false;
  }

  Future<void> setScriptureRefAdvancementEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scriptureRefAdvancementKey, value);
  }
}
