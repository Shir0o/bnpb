import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mobile screens use theme color roles instead of hardcoded swatches',
    () {
      const checkedFiles = [
        'lib/screens/add_contact_page.dart',
        'lib/screens/analytics_page.dart',
        'lib/screens/contact_details_page.dart',
        'lib/screens/home_page.dart',
        'lib/screens/settings_page.dart',
        'lib/screens/prayer_diary_page.dart',
        'lib/screens/add_family_page.dart',
        'lib/screens/ai_settings_page.dart',
        'lib/widgets/relationship_dialog.dart',
        'lib/widgets/people_card.dart',
      ];
      // `white` is intentionally not disallowed here: the design hardcodes
      // fixed white text/icons on colored or permanently-dark surfaces
      // (e.g. `color:#fff` on buttons/the AI card) regardless of theme, so
      // Colors.white is a legitimate choice, not a copy-pasted token.
      final disallowedSwatches = RegExp(
        r'Colors\.(blue|red|green|orange|purple|grey|black)',
      );
      // The exact light- and dark-mode Crisp Utility token hex values from
      // main.dart's _lightColorScheme/_darkColorScheme/CrispColorScheme.
      // A literal match means a token was copy-pasted instead of referenced
      // via Theme.of(context).colorScheme, which silently breaks whichever
      // brightness the literal wasn't written for. Pure white/black and
      // decorative (chart/avatar) colors are intentionally excluded since
      // they have legitimate theme-independent uses (e.g. white text on a
      // green button, per the design's own hardcoded `color:#fff`).
      // `0xFF127A6B` (light secondary/alt-teal) and `0xFFEEF2EF` (hairline)
      // are also excluded: the design itself hardcodes both as decorative,
      // theme-static colors (a chart-bar color, and icon tints on the
      // always-dark AI card) rather than driving them off a CSS token.
      final disallowedTokenHex = RegExp(
        r'Color\(0xFF(?:'
        r'0F1512|F1F5F2|8A988F|57635C|E6EBE7|3D4C44|C3CCC6|A9B3AD|'
        r'0D7A4F|EAF6EF|C25A3F|FBEEE9|FDF5F2|F0D9D0|D5DBD7|'
        r'22A36D|9AA79F|E9EFEB|1F2621|8B988F|2B332D|242C26|B6C2BA|4B564F|'
        r'5D6A62|E07A5F|331813|2A1611|4A2B21|37413B|151A17|0C1712|F2F5F3'
        r')\)',
      );
      // The Home page's AI recommendations card is a fixed near-black
      // surface in both themes (matching the design's `--ai-card` token),
      // so its priority-accent icon colors are deliberately theme-static
      // literals, not roles that should react to Theme.of(context).
      final allowedFixedDarkCard = RegExp(
        r'iconColor = const Color\(0xFF8A988F\);',
      );

      final violations = <String>[];
      for (final filePath in checkedFiles) {
        final lines = File(filePath).readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if ((disallowedSwatches.hasMatch(line) ||
                  disallowedTokenHex.hasMatch(line)) &&
              !allowedFixedDarkCard.hasMatch(line)) {
            violations.add('$filePath:${index + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Use Theme.of(context).colorScheme roles (or the '
            'CrispColorScheme extension) instead of hardcoded Crisp Utility '
            'token values, so colors react to light/dark mode.',
      );
    },
  );
}
