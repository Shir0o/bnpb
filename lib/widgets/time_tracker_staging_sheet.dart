import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bnpb/main.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/ai/time_tracker_ai_resolver.dart';
import 'package:bnpb/widgets/contact_multi_select.dart';

/// A bottom sheet for reviewing, editing, and confirming [CandidateInteraction]s
/// staged from Simple Time Tracker before importing them into BNPB.
class TimeTrackerStagingSheet extends StatefulWidget {
  final List<CandidateInteraction> candidates;
  final List<Contact> contacts;
  final ValueChanged<List<CandidateInteraction>> onConfirm;
  final VoidCallback? onDismiss;

  const TimeTrackerStagingSheet({
    super.key,
    required this.candidates,
    required this.contacts,
    required this.onConfirm,
    this.onDismiss,
  });

  @override
  State<TimeTrackerStagingSheet> createState() =>
      _TimeTrackerStagingSheetState();
}

class _TimeTrackerStagingSheetState extends State<TimeTrackerStagingSheet> {
  late List<CandidateInteraction> _items;
  // Filter state: null = All, 'unassigned' = no contact, else a contact id.
  String? _filter;
  bool _resolvingAi = false;

  @override
  void initState() {
    super.initState();
    _items = widget.candidates.map((e) => e.copyWith()).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  int get _selectedCount => _items.where((e) => e.selected).length;

  List<CandidateInteraction> get _filteredItems {
    if (_filter == null) return _items;
    if (_filter == 'unassigned') {
      return _items.where((e) => e.matchedContactIds.isEmpty).toList();
    }
    return _items.where((e) => e.matchedContactIds.contains(_filter)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy  h:mm a');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Time Tracker Staging Queue',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: _resolvingAi
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 20),
                tooltip: 'Resolve unmatched records with AI',
                onPressed: _resolvingAi ? null : _resolveUnmatchedWithAi,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  widget.onDismiss?.call();
                  Navigator.of(context).maybePop();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Review detected events from Simple Time Tracker before adding to BNPB history.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.secondaryText,
            ),
          ),
          const Divider(height: 20),
          _buildFilterRow(theme),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filteredItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return _buildCandidateTile(item, dateFormat, theme);
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  widget.onDismiss?.call();
                  Navigator.of(context).maybePop();
                },
                child: const Text('Later'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _selectedCount > 0
                    ? () {
                        final confirmed =
                            _items.where((e) => e.selected).toList();
                        widget.onConfirm(confirmed);
                        Navigator.of(context).maybePop();
                      }
                    : null,
                child: Text('Import $_selectedCount Selected'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(ThemeData theme) {
    final contacts = widget.contacts;
    // Contacts that actually appear in the queue.
    final matchedIds = <String>{
      for (final item in _items) ...item.matchedContactIds,
    };
    final relevantContacts =
        contacts.where((c) => matchedIds.contains(c.id)).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(
            label: 'All (${_items.length})',
            selected: _filter == null,
            onSelected: () => setState(() => _filter = null),
          ),
          _filterChip(
            label: 'Unassigned',
            selected: _filter == 'unassigned',
            onSelected: () => setState(() => _filter = 'unassigned'),
          ),
          for (final contact in relevantContacts)
            _filterChip(
              label: contact.fullName.isNotEmpty
                  ? contact.fullName
                  : contact.firstName,
              selected: _filter == contact.id,
              onSelected: () => setState(() => _filter = contact.id),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }

  Widget _buildCandidateTile(
    CandidateInteraction item,
    DateFormat dateFormat,
    ThemeData theme,
  ) {
    // Find matched contact names
    final matchedContacts = widget.contacts
        .where((c) => item.matchedContactIds.contains(c.id))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.selected,
            onChanged: (val) {
              setState(() {
                item.selected = val ?? false;
              });
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      tooltip: 'Resolve with AI',
                      onPressed: () => _resolveSingleWithAi(item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit summary',
                      onPressed: () => _editCandidate(item),
                    ),
                  ],
                ),
                Text(
                  '${dateFormat.format(item.occurredAt)} (${item.durationMinutes ?? 0}m)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondaryText,
                  ),
                ),
                if (item.possibleDuplicateOf != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: Colors.amber.shade700, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.amber.shade800),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.duplicateReason ??
                                'Possible duplicate of existing interaction',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final contact in matchedContacts)
                      Chip(
                        label: Text(
                          contact.fullName.isNotEmpty
                              ? contact.fullName
                              : contact.firstName,
                          style: const TextStyle(fontSize: 12),
                        ),
                        avatar: const CircleAvatar(
                          radius: 10,
                          child: Icon(Icons.person, size: 12),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setState(() {
                            item.matchedContactIds.remove(contact.id);
                          });
                        },
                      ),
                    ActionChip(
                      label: const Text('+ Add Contact',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () => _pickContact(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editCandidate(CandidateInteraction item) async {
    final controller = TextEditingController(text: item.summary);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Summary'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Summary'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      setState(() {
        item.summary = controller.text.trim();
      });
    }
  }

  Future<void> _pickContact(CandidateInteraction item) async {
    final selectedIds = await ContactMultiSelect.show(
      context,
      contacts: widget.contacts,
      initialSelectedIds: item.matchedContactIds.toSet(),
      title: 'Select Attendees',
    );

    if (selectedIds != null) {
      setState(() {
        item.matchedContactIds = selectedIds;
      });
    }
  }

  Future<void> _resolveSingleWithAi(CandidateInteraction item) async {
    final resolver = TimeTrackerAiResolver();
    final matched = await resolver.resolveContactsForCandidate(
      candidate: item,
      contacts: widget.contacts,
    );
    if (!mounted) return;
    if (matched.isNotEmpty) {
      setState(() {
        item.matchedContactIds = matched;
        item.selected = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Matched ${matched.length} contact(s) via AI')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts matched by AI')),
      );
    }
  }

  Future<void> _resolveUnmatchedWithAi() async {
    final unmatched = _items.where((e) => e.matchedContactIds.isEmpty).toList();
    if (unmatched.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unmatched candidates to resolve')),
      );
      return;
    }

    setState(() => _resolvingAi = true);
    final resolver = TimeTrackerAiResolver();
    var resolvedCount = 0;

    for (final item in unmatched) {
      final matched = await resolver.resolveContactsForCandidate(
        candidate: item,
        contacts: widget.contacts,
      );
      if (matched.isNotEmpty) {
        item.matchedContactIds = matched;
        item.selected = true;
        resolvedCount++;
      }
    }

    if (mounted) {
      setState(() => _resolvingAi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resolved $resolvedCount candidate(s) via AI')),
      );
    }
  }
}
