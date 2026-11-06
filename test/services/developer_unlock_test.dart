import 'package:bnpb/services/developer_unlock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('seven taps unlock and persist for this install', () async {
    final unlock = DeveloperUnlock();

    for (var tap = 0; tap < 6; tap++) {
      expect(await unlock.registerTap(), 7 - (tap + 1));
      expect(await unlock.isUnlocked(), isFalse);
    }

    expect(await unlock.registerTap(), 0);
    expect(await unlock.isUnlocked(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DeveloperUnlock.prefsKey), isTrue);
  });

  test('a tap after the gap starts a fresh run instead of finishing', () async {
    final unlock = DeveloperUnlock(
      tapGap: const Duration(milliseconds: 10),
    );

    for (var tap = 0; tap < 6; tap++) {
      await unlock.registerTap();
    }

    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Tap one of a fresh run, not the seventh of the old one.
    expect(await unlock.registerTap(), 6);
    expect(await unlock.isUnlocked(), isFalse);
  });

  test('lock puts the options away again', () async {
    final unlock = DeveloperUnlock();
    for (var tap = 0; tap < 7; tap++) {
      await unlock.registerTap();
    }
    expect(await unlock.isUnlocked(), isTrue);

    await unlock.lock();

    expect(await unlock.isUnlocked(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DeveloperUnlock.prefsKey), isFalse);
  });
}
