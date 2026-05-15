import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/relationship.dart';
import '../services/import_duplicate_detector.dart';

enum _GroupDecision { merge, keepAll, skip }

/// Review screen shown before committing an import when suspected duplicates
/// were detected. Returns the final list of contacts to import, or `null`
/// if the user cancels.
class ImportDuplicateReviewPage extends StatefulWidget {
  const ImportDuplicateReviewPage({
    super.key,
    required this.incoming,
    required this.groups,
  });

  final List<Contact> incoming;
  final List<DuplicateGroup> groups;

  @override
  State<ImportDuplicateReviewPage> createState() =>
      _ImportDuplicateReviewPageState();
}

class _ImportDuplicateReviewPageState extends State<ImportDuplicateReviewPage> {
  late final List<_GroupDecision> _decisions;

  @override
  void initState() {
    super.initState();
    _decisions =
        List<_GroupDecision>.filled(widget.groups.length, _GroupDecision.merge);
  }

  void _confirm() {
    final duplicateIds = <String>{};
    for (final g in widget.groups) {
      for (final c in g.members) {
        duplicateIds.add(c.id);
      }
    }

    final result = <Contact>[];
    // Carry over contacts that weren't part of any duplicate group.
    for (final c in widget.incoming) {
      if (!duplicateIds.contains(c.id)) result.add(c);
    }

    for (var i = 0; i < widget.groups.length; i++) {
      final group = widget.groups[i];
      switch (_decisions[i]) {
        case _GroupDecision.merge:
          result.add(mergeContacts(group.members));
        case _GroupDecision.keepAll:
          result.addAll(group.members);
        case _GroupDecision.skip:
          break;
      }
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review suspected duplicates'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel import',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Import'),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: widget.groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              '${widget.groups.length} possible duplicate '
              '${widget.groups.length == 1 ? "group" : "groups"} found. '
              'Choose what to do with each before importing.',
              style: Theme.of(context).textTheme.bodyMedium,
            );
          }
          final i = index - 1;
          return _GroupCard(
            group: widget.groups[i],
            decision: _decisions[i],
            onChanged: (d) => setState(() => _decisions[i] = d),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.decision,
    required this.onChanged,
  });

  final DuplicateGroup group;
  final _GroupDecision decision;
  final ValueChanged<_GroupDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.reason,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            for (final c in group.members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${c.displayName}'
                  '${c.phone != null && c.phone!.isNotEmpty ? " · ${c.phone}" : ""}'
                  '${c.email != null && c.email!.isNotEmpty ? " · ${c.email}" : ""}',
                ),
              ),
            const SizedBox(height: 8),
            SegmentedButton<_GroupDecision>(
              segments: const [
                ButtonSegment(
                  value: _GroupDecision.merge,
                  label: Text('Merge'),
                  icon: Icon(Icons.merge_type),
                ),
                ButtonSegment(
                  value: _GroupDecision.keepAll,
                  label: Text('Keep all'),
                  icon: Icon(Icons.group_add),
                ),
                ButtonSegment(
                  value: _GroupDecision.skip,
                  label: Text('Skip'),
                  icon: Icon(Icons.block),
                ),
              ],
              selected: {decision},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ],
        ),
      ),
    );
  }
}

/// Merges a duplicate group into a single contact: takes the first member's
/// id and required fields, fills optional fields from the first non-empty
/// value, and concatenates interactions / prayer requests / relationships
/// deduplicated by id.
@visibleForTesting
Contact mergeContacts(List<Contact> members) {
  assert(members.isNotEmpty);
  final primary = members.first;

  String? firstNonEmpty(String? Function(Contact) pick) {
    for (final c in members) {
      final v = pick(c);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  String firstNonEmptyRequired(String Function(Contact) pick, String fallback) {
    for (final c in members) {
      final v = pick(c);
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  final memberIds = {for (final c in members) c.id};
  String rewrite(String id) => memberIds.contains(id) ? primary.id : id;
  List<String> rewriteAll(List<String> ids) =>
      [for (final id in ids) rewrite(id)];

  final interactions = {
    for (final c in members)
      for (final x in c.interactions)
        x.syncId: x.copyWith(participantIds: rewriteAll(x.participantIds)),
  }.values.toList();
  final prayerRequests = {
    for (final c in members)
      for (final p in c.prayerRequests)
        p.syncId: p.copyWith(participantIds: rewriteAll(p.participantIds)),
  }.values.toList();
  final relationships = <String, Relationship>{};
  for (final c in members) {
    for (final r in c.relationships) {
      final source = rewrite(r.sourceContactId);
      final target = rewrite(r.targetContactId);
      if (source == target) continue;
      final rewritten = r.copyWith(
        sourceContactId: source,
        targetContactId: target,
      );
      relationships['$source->$target|${r.type}'] = rewritten;
    }
  }

  return primary.copyWith(
    firstName: firstNonEmptyRequired((c) => c.firstName, primary.firstName),
    middleName: firstNonEmptyRequired((c) => c.middleName, ''),
    lastName: firstNonEmpty((c) => c.lastName),
    nickname: firstNonEmpty((c) => c.nickname),
    location: firstNonEmpty((c) => c.location),
    email: firstNonEmpty((c) => c.email),
    phone: firstNonEmpty((c) => c.phone),
    firstMeetingNotes: firstNonEmpty((c) => c.firstMeetingNotes),
    notes: firstNonEmpty((c) => c.notes),
    interactions: interactions,
    prayerRequests: prayerRequests,
    relationships: relationships.values.toList(),
  );
}
