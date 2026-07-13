import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contact.dart';
import '../models/interaction.dart';
import 'contact_avatar.dart';

/// A reusable card summarizing contact insights, recent interactions, and
/// recognition cues to help quickly recall a person.
class PeopleCard extends StatelessWidget {
  const PeopleCard({
    super.key,
    required this.contact,
    this.onTap,
    this.trailing,
    this.highlightLabel,
    this.highlightText,
  });

  final Contact contact;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? highlightLabel;
  final String? highlightText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = _displayName(contact);
    final latestInteraction = _latestInteraction(contact);
    final subtitleDetails = _buildSubtitleDetails(contact);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Color(0xFFE6EBE7))),
      // Optimization: Removed Clip.antiAlias to avoid expensive saveLayer calls.
      // Clipping is handled by InkWell.borderRadius for splashes, and padding for content.
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        // Optimization: Isolate the static content from the InkWell ripple animation.
        // The ripple is painted on the Card (Material), so wrapping the content prevents
        // it from being repainted on every frame of the splash.
        child: RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ContactAvatar(contact: contact, radius: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16.5,
                                  color: const Color(0xFF0F1512))),
                          if (contact.nickname != null &&
                              contact.nickname!.isNotEmpty &&
                              contact.nickname!.toLowerCase() !=
                                  displayName.toLowerCase())
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Goes by ${contact.nickname}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          if (subtitleDetails.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: subtitleDetails,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (trailing != null)
                      trailing!
                    else if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.outline,
                      ),
                  ],
                ),
                if (latestInteraction != null) ...[
                  const SizedBox(height: 12),
                  _LatestInteractionSummary(interaction: latestInteraction),
                ],
                if (highlightLabel != null && highlightText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          highlightLabel!,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          highlightText!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _displayName(Contact contact) {
    if (contact.fullName.isNotEmpty) {
      return contact.fullName;
    }
    return contact.nickname ?? 'Unnamed Contact';
  }

  Interaction? _latestInteraction(Contact contact) {
    if (contact.interactions.isEmpty) {
      return null;
    }
    return contact.interactions.first;
  }

  List<Widget> _buildSubtitleDetails(Contact contact) {
    final details = <Widget>[];
    if (contact.location != null && contact.location!.isNotEmpty) {
      details.add(
        _SubtitleChip(
          icon: Icons.location_on_outlined,
          label: contact.location!,
        ),
      );
    }
    return details;
  }
}

class _SubtitleChip extends StatelessWidget {
  const _SubtitleChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestInteractionSummary extends StatelessWidget {
  const _LatestInteractionSummary({required this.interaction});

  final Interaction interaction;

  static final _dateFormat = DateFormat.yMMMd();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _dateFormat.format(interaction.occurredAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last interaction • $dateText',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  interaction.summary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                if ((interaction.location ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Location: ${interaction.location}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
