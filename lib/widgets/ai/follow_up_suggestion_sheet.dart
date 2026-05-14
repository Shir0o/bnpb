import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../db/db_helper.dart';
import '../../services/ai/ai_services.dart';
import '../../services/ai/follow_up_suggestion_service.dart';
import '../../services/reminder_coordinator.dart';

/// Bottom sheet shown after a user logs an interaction. Generates 2-4
/// follow-up suggestions on-device and lets the user accept one with a tap,
/// which schedules a reminder via [Interaction.followUpAt].
class FollowUpSuggestionSheet extends StatefulWidget {
  const FollowUpSuggestionSheet({
    super.key,
    required this.contact,
    required this.interaction,
    required this.onInteractionUpdated,
  });

  final Contact contact;
  final Interaction interaction;
  final ValueChanged<Interaction> onInteractionUpdated;

  /// Shows the sheet only when AI features are enabled, the model is loaded,
  /// and the interaction has enough content to summarize. Returns silently
  /// otherwise so the existing post-save flow is unaffected.
  static Future<void> maybeShow(
    BuildContext context, {
    required Contact contact,
    required Interaction interaction,
    required ValueChanged<Interaction> onInteractionUpdated,
  }) async {
    if (interaction.id == null) return;
    if (!await AiServices().isReady()) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FollowUpSuggestionSheet(
        contact: contact,
        interaction: interaction,
        onInteractionUpdated: onInteractionUpdated,
      ),
    );
  }

  @override
  State<FollowUpSuggestionSheet> createState() =>
      _FollowUpSuggestionSheetState();
}

class _FollowUpSuggestionSheetState extends State<FollowUpSuggestionSheet> {
  late Future<List<FollowUpSuggestion>> _future;
  bool _scheduling = false;

  @override
  void initState() {
    super.initState();
    _future = AiServices().followUp.suggest(widget.interaction);
  }

  Future<void> _accept(FollowUpSuggestion suggestion) async {
    if (_scheduling) return;
    setState(() => _scheduling = true);
    final scheduledFor = suggestion.suggestedDate(DateTime.now());
    final updated = widget.interaction.copyWith(
      followUpAt: scheduledFor,
      updatedAt: DateTime.now(),
    );
    try {
      await DBHelper().updateInteraction(updated);
      await ReminderCoordinator().syncInteractionReminder(
        widget.contact,
        updated,
        silent: true,
      );
      widget.onInteractionUpdated(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Follow-up scheduled for ${DateFormat.MMMd().format(scheduledFor)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _scheduling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule follow-up: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Suggested follow-ups',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Generated on-device from this interaction',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<FollowUpSuggestion>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Could not generate suggestions.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  );
                }
                final items = snapshot.data ?? const <FollowUpSuggestion>[];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No suggestions for this note.'),
                  );
                }
                return Column(
                  children: [
                    for (final s in items)
                      _SuggestionTile(
                        suggestion: s,
                        disabled: _scheduling,
                        onTap: () => _accept(s),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _scheduling ? null : () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.disabled,
  });

  final FollowUpSuggestion suggestion;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final whenLabel = suggestion.daysFromNow == 1
        ? 'tomorrow'
        : 'in ${suggestion.daysFromNow} days';
    return Card(
      child: ListTile(
        title: Text(suggestion.action),
        subtitle: Text([
          whenLabel,
          if (suggestion.reason != null && suggestion.reason!.isNotEmpty)
            suggestion.reason!,
        ].join(' • ')),
        trailing: const Icon(Icons.notifications_outlined),
        onTap: disabled ? null : onTap,
      ),
    );
  }
}
