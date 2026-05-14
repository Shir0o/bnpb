import 'package:flutter/material.dart';

import '../../models/interaction.dart';
import '../../services/ai/ai_services.dart';

/// Card placed on `contact_details_page.dart` that shows a 2-3 sentence
/// on-device summary of the contact's recent interactions. Only renders
/// when [AiServices.isReady] resolves true, so the card disappears
/// entirely on devices where AI is off or the model isn't loaded.
class InteractionSummaryCard extends StatefulWidget {
  const InteractionSummaryCard({
    super.key,
    required this.interactions,
  });

  final List<Interaction> interactions;

  @override
  State<InteractionSummaryCard> createState() => _InteractionSummaryCardState();
}

class _InteractionSummaryCardState extends State<InteractionSummaryCard> {
  Future<String>? _future;
  bool _aiReady = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkReady();
  }

  @override
  void didUpdateWidget(covariant InteractionSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Invalidate the cached summary when the underlying interactions change,
    // so adding a new interaction doesn't leave a stale digest on screen.
    if (oldWidget.interactions.length != widget.interactions.length) {
      setState(() => _future = null);
    }
  }

  Future<void> _checkReady() async {
    final ready = await AiServices().isReady();
    if (!mounted) return;
    setState(() {
      _aiReady = ready;
      _checking = false;
    });
  }

  void _generate() {
    setState(() {
      _future = AiServices().interactionSummary.summarize(widget.interactions);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const SizedBox.shrink();
    if (!_aiReady) return const SizedBox.shrink();
    if (widget.interactions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('AI summary', style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _generate,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_future == null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  'Tap refresh to summarize this contact\'s recent '
                  'interactions on-device.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              FutureBuilder<String>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'Could not generate summary.',
                      style: theme.textTheme.bodyMedium,
                    );
                  }
                  final text = snapshot.data?.trim() ?? '';
                  if (text.isEmpty) {
                    return Text(
                      'Not enough content to summarize yet.',
                      style: theme.textTheme.bodyMedium,
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(text, style: theme.textTheme.bodyMedium),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
