import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contact.dart';
import '../models/interaction.dart';

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

    // Optimization: Wrap in RepaintBoundary to isolate ripple animations and internal scrolling from the parent list, reducing unnecessary repaints of siblings.
    return RepaintBoundary(
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  CircleAvatar(
                    radius: 24,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName.substring(0, 1).toUpperCase()
                          : '?',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium,
                        ),
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
              if (contact.recognitionKeywords.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Keywords', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: contact.recognitionKeywords
                      .map(
                        (keyword) => Chip(
                          label: Text(keyword),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (contact.recognitionReminders.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Reminders', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                ...contact.recognitionReminders.map(
                  (reminder) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          size: 18,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reminder,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (contact.recognitionPhotoUris.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Recognition photos', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final cue = contact.recognitionPhotoUris[index];
                      final provider = _resolveImage(cue);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 80,
                          height: 80,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: provider != null
                              ? Image(
                                  // Resize image to display size to save memory
                                  image: ResizeImage(
                                    provider,
                                    width: (80 *
                                            MediaQuery.of(context)
                                                .devicePixelRatio)
                                        .toInt(),
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.photo_outlined),
                                      const SizedBox(height: 4),
                                      Text(
                                        cue.length > 10
                                            ? '${cue.substring(0, 10)}…'
                                            : cue,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: contact.recognitionPhotoUris.length,
                  ),
                ),
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
    ));
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
    if (contact.tags.isNotEmpty) {
      details.addAll(
        contact.tags.take(3).map(
              (tag) => _SubtitleChip(
                icon: Icons.style_outlined,
                label: tag,
              ),
            ),
      );
      if (contact.tags.length > 3) {
        details.add(
          _SubtitleChip(
            icon: Icons.tag,
            label: '+${contact.tags.length - 3}',
          ),
        );
      }
    }
    return details;
  }

  ImageProvider<Object>? _resolveImage(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasAbsolutePath) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        return NetworkImage(value);
      }
    }
    return null;
  }
}

class _SubtitleChip extends StatelessWidget {
  const _SubtitleChip({
    required this.icon,
    required this.label,
  });

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = DateFormat.yMMMd().format(interaction.occurredAt);

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
