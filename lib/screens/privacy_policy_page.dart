import 'package:flutter/material.dart';

import '../content/privacy_policy.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

/// Displays the privacy policy and personal usage guidance inside the app.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = kPrivacyPolicyText.trim().split('\n\n');

    return HideOnScrollScaffold(
      appBar: AppBar(title: const Text('Privacy & usage')),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: sections.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final text = sections[index];
          final isTitle = index == 0;
          return Text(
            text,
            style: isTitle
                ? theme.textTheme.headlineSmall
                : theme.textTheme.bodyMedium,
          );
        },
      ),
    );
  }
}
