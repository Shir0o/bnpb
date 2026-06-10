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
      ];
      final disallowedSwatches = RegExp(
        r'Colors\.(blue|red|green|orange|purple|grey|black|white)',
      );

      final violations = <String>[];
      for (final filePath in checkedFiles) {
        final lines = File(filePath).readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          if (disallowedSwatches.hasMatch(lines[index])) {
            violations.add('$filePath:${index + 1}: ${lines[index].trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Use Theme.of(context).colorScheme roles on shared mobile UI.',
      );
    },
  );
}
