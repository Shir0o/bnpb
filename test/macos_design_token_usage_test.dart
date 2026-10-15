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
      r'FF2AA06E|FF7FC7A6|FFA9DCC4|FFCDEADD|FF4C8B6E'
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

  test('macOS surfaces enforce Hairline Containment Rule (zero boxShadow)', () {
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

    final violations = <String>[];
    for (final filePath in checkedFiles) {
      final lines = File(filePath).readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.contains('boxShadow')) {
          violations.add('$filePath:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'No drop shadows allowed per Hairline Containment Rule (DESIGN.md:200).',
    );
  });

  test('macOS surfaces enforce Typography font consistency (no googleSans)',
      () {
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

    final violations = <String>[];
    for (final filePath in checkedFiles) {
      final lines = File(filePath).readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.contains('GoogleFonts.googleSans')) {
          violations.add('$filePath:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Use Plus Jakarta Sans per DESIGN.md:149.',
    );
  });

  test('macOS surfaces use showMacModal instead of Navigator.push for details',
      () {
    const checkedFiles = [
      'lib/screens/macos/macos_contacts_view.dart',
      'lib/screens/macos/macos_prayer_diary_view.dart',
      'lib/screens/macos/macos_ask_view.dart',
    ];

    final violations = <String>[];
    for (final filePath in checkedFiles) {
      final lines = File(filePath).readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.contains('Navigator.push') ||
            line.contains('Navigator.of(context).push')) {
          violations.add('$filePath:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Desktop must use showMacModal instead of mobile Navigator.push.',
    );
  });

  test('macOS analytics headline card follows Sanctuary Card Rule', () {
    final content =
        File('lib/screens/macos/macos_analytics_view.dart').readAsStringSync();
    expect(
      content.contains('aiCardBg'),
      isFalse,
      reason:
          'aiCardBg is strictly reserved for AI synthesis/search (DESIGN.md:145).',
    );
  });
}
