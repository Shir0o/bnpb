import 'package:shared_preferences/shared_preferences.dart';

/// Handles persistence for onboarding related state so the wizard only
/// appears when it is still relevant.
class OnboardingService {
  OnboardingService();

  static const String _completedKey = 'onboarding.completed';

  /// Returns `true` when the onboarding flow should be surfaced again.
  Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_completedKey) ?? false);
  }

  /// Marks the onboarding flow as complete so it is not shown again on
  /// subsequent launches.
  Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }

  /// Resets the onboarding completion flag. Useful for integration tests or
  /// if the application ever needs to resurface the flow deliberately.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
  }
}
