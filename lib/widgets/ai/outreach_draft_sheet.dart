import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../services/ai/ai_services.dart';

/// Bottom sheet that shows on-device conversation openers grounded in
/// the focal contact's recent interactions and active prayer requests.
/// Each hook can be copied to the clipboard so the user can paste it
/// into the messaging app of their choice.
class OutreachDraftSheet extends StatefulWidget {
  const OutreachDraftSheet({
    super.key,
    required this.contact,
    required this.interactions,
  });

  final Contact contact;
  final List<Interaction> interactions;

  /// Opens the sheet only when AI is ready. Returns silently otherwise so
  /// callers don't need to guard the call site.
  static Future<void> maybeShow(
    BuildContext context, {
    required Contact contact,
    required List<Interaction> interactions,
  }) async {
    if (!await AiServices().isReady()) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => OutreachDraftSheet(
        contact: contact,
        interactions: interactions,
      ),
    );
  }

  @override
  State<OutreachDraftSheet> createState() => _OutreachDraftSheetState();
}

class _OutreachDraftSheetState extends State<OutreachDraftSheet> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<String>> _load() async {
    final prayers =
        await DBHelper().getPrayerRequestsForContact(widget.contact.id);
    return AiServices().outreach.suggestHooks(
          recentInteractions: widget.interactions,
          activePrayerRequests: prayers,
        );
  }

  Future<void> _copy(String hook) async {
    await Clipboard.setData(ClipboardData(text: hook));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Suggested openers',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Generated on-device from recent interactions and active '
              'prayer requests. Tap to copy.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<String>>(
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
                    child: Text(
                      'Could not generate openers.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                final items = snapshot.data ?? const <String>[];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Not enough recent context to suggest an opener yet.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final hook in items)
                      Card(
                        child: ListTile(
                          title: Text(hook),
                          trailing: const Icon(Icons.copy_outlined),
                          onTap: () => _copy(hook),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
