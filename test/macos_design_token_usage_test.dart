import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS surfaces use theme color roles', () {
    const checkedFiles = [
      'lib/screens/macos/macos_shell.dart',
      'lib/screens/macos/macos_contacts_view.dart',
      'lib/screens/macos/contact_card.dart',
      'lib/screens/macos/macos_active_contacts_view.dart',
      'lib/screens/macos/macos_contact_details_page.dart',
      'lib/screens/macos/macos_prayer_diary_view.dart',
      'lib/screens/macos/macos_settings_view.dart',
      'lib/screens/macos/prayer_diary_entry.dart',
    ];
    final disallowed = RegExp(
      r'Colors\.(blue|red|green|orange|purple|grey|black|white)|Color\(0x',
    );
    final allowedTrafficLight = RegExp(
      r'Color\(0x(?:FFFF5F57|FFE0443E|FFFEBC2E|FFD89E24|FF28C840|FF1AAB29)\)',
    );

    final violations = <String>[];
    for (final filePath in checkedFiles) {
      final lines = File(filePath).readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (disallowed.hasMatch(line) && !allowedTrafficLight.hasMatch(line)) {
          violations.add('$filePath:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Use Theme.of(context).colorScheme roles on macOS UI surfaces.',
    );
  });
}
