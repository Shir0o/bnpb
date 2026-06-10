import 'package:shared_preferences/shared_preferences.dart';

/// Which AI backend is active when the feature gate is enabled.
///
/// [local] is the default and uses the on-device Gemma model. No data
/// leaves the device. [cloud] routes every AI request to Google's
/// Gemini API using a user-supplied API key — see [SecurityService]
/// for credential storage and [AiSettingsPage] for the opt-in flow.
enum AiBackend { local, cloud }

/// User-controlled opt-in flag for AI features and the backend that
/// services them.
///
/// BNPB's privacy posture is offline-first, so AI is off by default
/// and only enabled after the user explicitly opts in. When enabled,
/// the on-device backend is the default; the cloud backend is a
/// further explicit opt-in with separate disclosure.
class AiFeatureGate {
  AiFeatureGate();

  static const String _enabledKey = 'ai.features.enabled';
  static const String _backendKey = 'ai.features.backend';
  static const String _backendCloud = 'cloud';
  static const String _backendLocal = 'local';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static const String _showSuggestionsOnSaveKey =
      'ai.features.show_suggestions_on_save';

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Returns the configured backend. Defaults to [AiBackend.local].
  Future<AiBackend> backend() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backendKey);
    return raw == _backendCloud ? AiBackend.cloud : AiBackend.local;
  }

  Future<void> setBackend(AiBackend value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _backendKey,
      value == AiBackend.cloud ? _backendCloud : _backendLocal,
    );
  }

  Future<bool> isShowSuggestionsOnSaveEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showSuggestionsOnSaveKey) ?? true;
  }

  Future<void> setShowSuggestionsOnSaveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showSuggestionsOnSaveKey, value);
  }
}
