import 'package:shared_preferences/shared_preferences.dart';

/// Android-style developer options, in miniature.
///
/// The CISA Tracker Sync settings stay out of Settings until the version
/// number is tapped seven times within a rolling gap. Visibility only: the
/// sync token still lives in secure storage, and this does not gate it.
class DeveloperUnlock {
  DeveloperUnlock({
    this.tapsRequired = 7,
    this.tapGap = const Duration(milliseconds: 1500),
  });

  /// Preference key holding whether this install has been unlocked.
  static const String prefsKey = 'developerUnlock';

  final int tapsRequired;
  final Duration tapGap;

  int _taps = 0;
  DateTime? _lastTap;

  Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  /// Registers one tap on the version number.
  ///
  /// Returns the number of taps still needed, or 0 when this tap unlocked the
  /// developer options.
  Future<int> registerTap() async {
    final now = DateTime.now();
    final last = _lastTap;
    _taps = (last == null || now.difference(last) > tapGap) ? 1 : _taps + 1;
    _lastTap = now;
    if (_taps < tapsRequired) return tapsRequired - _taps;

    _taps = 0;
    _lastTap = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
    return 0;
  }

  /// Puts the integration settings away again.
  Future<void> lock() async {
    _taps = 0;
    _lastTap = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, false);
  }
}
