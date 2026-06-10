import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ai/ai_services.dart';
import '../skeleton_loader.dart';

/// Bottom sheet that runs the on-device [AutoTagService] against a free-text
/// note and lets the user pick which suggested tags to keep. Accepted tags
/// are returned to the caller as a list of normalized snake_case strings;
/// the caller decides how to persist them (in v1, the interaction editor
/// appends them inline to the notes field as `#tag` tokens to avoid a DB
/// migration).
class TagSuggestionSheet extends StatefulWidget {
  const TagSuggestionSheet({
    super.key,
    required this.noteText,
    this.existingTags = const <String>{},
  });

  final String noteText;

  /// Tags already present in the note (e.g. parsed from `#tag` tokens).
  /// These are pre-filtered from the suggested set so we don't ask the user
  /// to re-accept tags they already have.
  final Set<String> existingTags;

  /// Returns the list of accepted tags, or an empty list if the user
  /// dismissed without accepting. Returns `null` only when AI is not ready
  /// and the sheet was suppressed — callers can treat that as "no-op".
  static Future<List<String>?> maybeShow(
    BuildContext context, {
    required String noteText,
    Set<String> existingTags = const <String>{},
  }) async {
    if (noteText.trim().isEmpty) return null;
    if (!await AiServices().isReady()) return null;
    if (!context.mounted) return null;
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) =>
          TagSuggestionSheet(noteText: noteText, existingTags: existingTags),
    );
  }

  @override
  State<TagSuggestionSheet> createState() => _TagSuggestionSheetState();
}

class _TagSuggestionSheetState extends State<TagSuggestionSheet> {
  StreamSubscription<List<String>>? _sub;
  final Set<String> _selected = <String>{};
  List<String> _suggested = const <String>[];
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sub = AiServices().autoTag.suggestTagsStream(widget.noteText).listen(
      (tags) {
        if (!mounted) return;
        final filtered = tags
            .where((t) => !widget.existingTags.contains(t))
            .toList(growable: false);
        setState(() {
          _suggested = filtered;
        });
      },
      onError: (Object e, StackTrace _) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _done = true;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _done = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
              'Suggested tags',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Generated on-device from this note. Tap to include or exclude.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _buildBody(context),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<String>[]),
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected.toList()),
                  child: const Text('Add tags'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Could not generate tags.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (_suggested.isEmpty) {
      if (_done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('No new tags for this note.'),
        );
      }
      return const _TagChipSkeleton();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final tag in _suggested)
          FilterChip(
            label: Text('#$tag'),
            selected: _selected.contains(tag),
            onSelected: (on) {
              setState(() {
                if (on) {
                  _selected.add(tag);
                } else {
                  _selected.remove(tag);
                }
              });
            },
          ),
        if (!_done) const _StreamingSkeletonChips(),
      ],
    );
  }
}

class _StreamingSkeletonChips extends StatelessWidget {
  const _StreamingSkeletonChips();

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final w in const <double>[72, 88])
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: SkeletonBox(
                width: w,
                height: 32,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagChipSkeleton extends StatelessWidget {
  const _TagChipSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final w in const <double>[88, 104, 72])
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: SkeletonBox(
                width: w,
                height: 32,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}
