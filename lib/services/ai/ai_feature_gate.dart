import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled opt-in flag for on-device AI features.
///
/// BNPB's privacy posture is offline-first, so AI is off by default and
/// only enabled after the user explicitly opts in (and the model has been
/// downloaded). Callers should check [isEnabled] before invoking any
/// AI-powered code path.
class AiFeatureGate {
  AiFeatureGate();

  static const String _enabledKey = 'ai.features.enabled';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
