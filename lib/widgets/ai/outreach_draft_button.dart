import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../services/ai/ai_services.dart';
import 'outreach_draft_sheet.dart';

/// Small button placed on the contact details page that opens the
/// [OutreachDraftSheet]. Self-gates on [AiServices.isReady] so it
/// disappears entirely when AI is off.
class OutreachDraftButton extends StatefulWidget {
  const OutreachDraftButton({
    super.key,
    required this.contact,
    required this.interactions,
  });

  final Contact contact;
  final List<Interaction> interactions;

  @override
  State<OutreachDraftButton> createState() => _OutreachDraftButtonState();
}

class _OutreachDraftButtonState extends State<OutreachDraftButton> {
  bool _ready = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ready = await AiServices().isReady();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || !_ready) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('Suggest opener'),
          onPressed: () => OutreachDraftSheet.maybeShow(
            context,
            contact: widget.contact,
            interactions: widget.interactions,
          ),
        ),
      ),
    );
  }
}
