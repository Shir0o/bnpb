import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/interaction.dart';

const Map<String, String> _mediumLabels = {
  'in_person': 'In-person',
  'call': 'Call',
  'message': 'Message',
  'online': 'Online Meeting',
  'other': 'Other',
};

const Map<String, IconData> _mediumIcons = {
  'in_person': Icons.people_outline,
  'call': Icons.phone_outlined,
  'message': Icons.chat_bubble_outline,
  'online': Icons.videocam_outlined,
  'other': Icons.more_horiz,
};

class InteractionTimelineTile extends StatelessWidget {
  const InteractionTimelineTile({
    super.key,
    required this.interaction,
    required this.isFirst,
    required this.isLast,
    required this.displayNameResolver,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.isEditing = false,
  });

  final Interaction interaction;
  final bool isFirst;
  final bool isLast;
  final String Function(String) displayNameResolver;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicatorColor = interaction.markForPrayer
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;

    final onIndicatorColor = interaction.markForPrayer
        ? theme.colorScheme.onSecondary
        : theme.colorScheme.onPrimary;
    final lineColor = theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Stack(
          children: [
            // Timeline line and dot
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 48,
              child: Column(
                children: [
                  if (!isFirst)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: lineColor,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: indicatorColor.withValues(alpha: 0.28),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      interaction.markForPrayer
                          ? Icons.volunteer_activism
                          : Icons.event,
                      size: 16,
                      color: onIndicatorColor,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: lineColor,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ),
            // Interaction Card
            Padding(
              padding: const EdgeInsets.only(left: 60),
              child: _buildInteractionCard(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionCard(BuildContext context) {
    final theme = Theme.of(context);
    final mediumLabel = _mediumLabels[interaction.medium] ?? interaction.medium;
    final mediumIcon = _mediumIcons[interaction.medium] ?? Icons.forum_outlined;

    final occurredAtLabel =
        DateFormat.yMMMd().add_jm().format(interaction.occurredAt);
    final participantBadges = _buildParticipantBadges(context);
    final metadataPills = <Widget>[
      _buildInfoPill(context, icon: mediumIcon, label: mediumLabel),
      if (interaction.durationMinutes != null)
        _buildInfoPill(
          context,
          icon: Icons.timer_outlined,
          label: '${interaction.durationMinutes} min',
        ),
      if (interaction.markForPrayer)
        _buildInfoPill(
          context,
          icon: Icons.self_improvement,
          label: 'Prayer focus',
        ),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    mediumIcon,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                occurredAtLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            Icon(
                              interaction.markForPrayer
                                  ? Icons.self_improvement_outlined
                                  : Icons.event_note_outlined,
                              size: 16,
                              color: interaction.markForPrayer
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          interaction.summary,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (participantBadges.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: participantBadges,
                          ),
                        ],
                        if (interaction.location != null &&
                            interaction.location!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              interaction.location!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (interaction.category != null &&
                            interaction.category!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              interaction.category!,
                              style: theme.textTheme.labelSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isEditing)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit interaction',
                          onPressed: onEdit,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete interaction',
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                ],
              ),
              if (metadataPills.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: metadataPills,
                ),
              ],
              if (interaction.followUpAt != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.alarm_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        DateFormat.MMMd()
                            .add_jm()
                            .format(interaction.followUpAt!),
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParticipantBadges(BuildContext context) {
    if (interaction.participantIds.isEmpty) {
      return const [];
    }

    final theme = Theme.of(context);
    return interaction.participantIds.toSet().map((participantId) {
      final name = displayNameResolver(participantId);
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

      return Chip(
        avatar: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: theme.colorScheme.primary,
          child: Text(initial),
        ),
        label: Text(name),
        visualDensity: VisualDensity.compact,
      );
    }).toList();
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return pill;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: pill,
      ),
    );
  }
}
