import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import '../models/prayer_request.dart';

/// One request in the prayer diary: who it is for, the request, its prayer
/// record, and either the quick actions (pending) or its outcome (closed).
///
/// Answering or archiving first expands an inline, optional comment field;
/// the status change is only sent once the user confirms it.
class PrayerDiaryCard extends StatefulWidget {
  const PrayerDiaryCard({
    super.key,
    required this.request,
    required this.names,
    required this.initials,
    required this.prayedDates,
    required this.onOpen,
    required this.onTogglePrayed,
    required this.onSetStatus,
    this.now,
  });

  final PrayerRequest request;

  /// Participant names, already joined for display.
  final String names;
  final String initials;

  /// Days this request was prayed for, ascending.
  final List<DateTime> prayedDates;

  final VoidCallback onOpen;
  final VoidCallback onTogglePrayed;

  /// Moves the request to a status; [comment] is null when left blank.
  final Future<void> Function(PrayerRequestStatus status, String? comment)
      onSetStatus;

  /// Overrides "today" for tests.
  final DateTime? now;

  @override
  State<PrayerDiaryCard> createState() => _PrayerDiaryCardState();
}

class _PrayerDiaryCardState extends State<PrayerDiaryCard> {
  final TextEditingController _comment = TextEditingController();

  /// The status being composed (answered or archived), or null when the
  /// comment field is closed.
  PrayerRequestStatus? _composing;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _startComposing(PrayerRequestStatus status) {
    _comment.clear();
    setState(() => _composing = status);
  }

  Future<void> _confirm() async {
    final status = _composing!;
    final text = _comment.text.trim();
    setState(() => _composing = null);
    await widget.onSetStatus(status, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final request = widget.request;
    final isPending = request.status == PrayerRequestStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(colorScheme),
          const SizedBox(height: 10),
          _buildRecord(colorScheme),
          if (!isPending) ...[
            const SizedBox(height: 10),
            _buildOutcome(colorScheme),
          ],
          if (isPending && _composing != null) ...[
            const SizedBox(height: 10),
            _buildComposer(colorScheme),
          ],
          if (isPending && _composing == null) ...[
            const SizedBox(height: 10),
            _buildActions(colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final request = widget.request;
    final (pillLabel, pillBg, pillFg) = switch (request.status) {
      PrayerRequestStatus.pending => (
          'Praying',
          colorScheme.hairline,
          colorScheme.iconColor,
        ),
      PrayerRequestStatus.answered => (
          'Answered',
          colorScheme.greenTint,
          colorScheme.primary,
        ),
      PrayerRequestStatus.archived => (
          'Archived',
          colorScheme.hairline,
          colorScheme.secondaryText,
        ),
    };
    final category = request.category?.trim() ?? '';
    final requested = 'requested ${_formatDay(request.requestedAt)}';
    final meta = category.isEmpty
        ? '${requested[0].toUpperCase()}${requested.substring(1)}'
        : '$category · $requested';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.greenTint,
            shape: BoxShape.circle,
          ),
          child: Text(
            widget.initials,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.names,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      pillLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: pillFg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(6),
                child: Text(
                  request.description,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecord(ColorScheme colorScheme) {
    final dates = widget.prayedDates;
    final String record;
    if (dates.isEmpty) {
      record = 'Not prayed for yet';
    } else {
      record = 'Prayed ${dates.length}× · '
          '${_prayedToday ? 'today' : 'last ${_formatDay(dates.last)}'}';
    }
    final recent = dates.reversed.take(3).toList().reversed.map(_formatDay);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              record,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          if (recent.isNotEmpty)
            Text(
              recent.join(' · '),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.secondaryText,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutcome(ColorScheme colorScheme) {
    final request = widget.request;
    final answered = request.status == PrayerRequestStatus.answered;
    final at = answered ? request.answeredAt : request.archivedAt;
    final label = [
      answered ? 'Answered' : 'Archived',
      if (at != null) _formatDay(at),
    ].join(' ');
    final comment = request.reflectionNotes?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 10),
      decoration: BoxDecoration(
        color: answered ? colorScheme.greenTint : colorScheme.surfaceTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: answered
                        ? colorScheme.primary
                        : colorScheme.secondaryText,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    widget.onSetStatus(PrayerRequestStatus.pending, null),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Reopen'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              comment.isEmpty ? 'No comment' : comment,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: comment.isEmpty
                    ? colorScheme.secondaryText
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(ColorScheme colorScheme) {
    final answering = _composing == PrayerRequestStatus.answered;
    final confirmBg = answering ? colorScheme.primary : colorScheme.iconColor;
    final confirmFg = answering ? colorScheme.onPrimary : colorScheme.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          answering ? 'How was it answered?' : 'Why archive it?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _comment,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 14, height: 1.45),
          decoration: const InputDecoration(hintText: 'Optional comment'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _composing = null),
              style: _buttonStyle(
                colorScheme,
                bg: colorScheme.surface,
                fg: colorScheme.onSurface,
                border: colorScheme.cardBorder,
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _confirm,
              style: _buttonStyle(
                colorScheme,
                bg: confirmBg,
                fg: confirmFg,
                border: confirmBg,
              ),
              child: Text(answering ? 'Mark answered' : 'Archive'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(ColorScheme colorScheme) {
    final prayed = _prayedToday;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            toggled: prayed,
            child: OutlinedButton.icon(
              onPressed: widget.onTogglePrayed,
              icon: const Icon(Icons.check, size: 14),
              label: Text(prayed ? 'Prayed today' : 'Prayed'),
              style: _buttonStyle(
                colorScheme,
                bg: prayed ? colorScheme.primary : colorScheme.greenTint,
                fg: prayed ? colorScheme.onPrimary : colorScheme.primary,
                border: prayed
                    ? colorScheme.primary
                    : colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _startComposing(PrayerRequestStatus.answered),
            style: _neutralStyle(colorScheme),
            child: const Text('Answered'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _startComposing(PrayerRequestStatus.archived),
            style: _neutralStyle(colorScheme),
            child: const Text('Archive'),
          ),
        ),
      ],
    );
  }

  ButtonStyle _neutralStyle(ColorScheme colorScheme) => _buttonStyle(
        colorScheme,
        bg: colorScheme.surface,
        fg: colorScheme.onSurface,
        border: colorScheme.cardBorder,
      );

  ButtonStyle _buttonStyle(
    ColorScheme colorScheme, {
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return OutlinedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    );
  }

  DateTime get _today => widget.now ?? DateTime.now();

  bool get _prayedToday {
    if (widget.prayedDates.isEmpty) return false;
    final last = widget.prayedDates.last;
    final today = _today;
    return last.year == today.year &&
        last.month == today.month &&
        last.day == today.day;
  }

  /// "Nov 3", with the year added when it isn't this year.
  String _formatDay(DateTime date) {
    final format =
        date.year == _today.year ? DateFormat.MMMd() : DateFormat.yMMMd();
    return format.format(date);
  }
}
