import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS surfaces use theme color roles', () {
    const checkedFiles = [
      'lib/screens/macos/macos_shell.dart',
      'lib/screens/macos/macos_contacts_view.dart',
      'lib/screens/macos/macos_contact_details_page.dart',
      'lib/screens/macos/macos_prayer_diary_view.dart',
      'lib/screens/macos/macos_settings_view.dart',
      'lib/screens/macos/prayer_diary_entry.dart',
      'lib/screens/macos/macos_analytics_view.dart',
      'lib/screens/macos/macos_ask_view.dart',
      'lib/screens/macos/macos_add_view.dart',
    ];
    // `white` is intentionally not disallowed here: the design hardcodes
    // fixed white text/icons on colored or permanently-dark surfaces (e.g.
    // the AI card, a green-filled stat card) regardless of theme, mirroring
    // the same carve-out in test/design_token_usage_test.dart.
    final disallowed = RegExp(
      r'Colors\.(blue|red|green|orange|purple|grey|black)|Color\(0x',
    );
    // The Crisp Utility desktop design's always-dark AI card (Ask input,
    // sidebar follow-up card, Analytics headline card) uses a fixed set of
    // decorative accent literals that don't come from a CSS token and are
    // deliberately theme-static, not roles that should react to
    // Theme.of(context) — same rationale as the mobile
    // design_token_usage_test.dart's `allowedFixedDarkCard` carve-out.
    final allowedFixedDarkCard = RegExp(
      r'Color\(0x(?:'
      r'FF5FE0A0|FF94A49B|FFE8EDE9|FF3A1F1F|FFFF8C7A|FFBFE6D1|'
      r'FF2AA06E|FF7FC7A6|FFA9DCC4|FFCDEADD'
      r')\)',
    );

    final violations = <String>[];
    for (final filePath in checkedFiles) {
      final lines = File(filePath).readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (disallowed.hasMatch(line) && !allowedFixedDarkCard.hasMatch(line)) {
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
