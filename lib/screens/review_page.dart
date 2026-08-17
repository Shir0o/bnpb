import 'package:flutter/material.dart';

import '../main.dart' show CrispColorScheme;
import '../db/db_helper.dart';
import '../services/contact_stage_service.dart';
import '../services/period_review_service.dart';
import '../widgets/crisp_toast.dart';
import 'contact_details_page.dart';

/// Period review — "who actually moved" over a month, semester, or year.
///
/// Mirrors the design's Review screen: period chips, verdict, movement funnel,
/// marks, intention, care, effort, and "what didn't happen".
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.initialPeriod = ReviewPeriod.month});

  final ReviewPeriod initialPeriod;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final PeriodReviewService _service = PeriodReviewService();
  late ReviewPeriod _period;
  PeriodReviewData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _service.build(period: _period);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  void _selectPeriod(ReviewPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _load();
  }

  Future<void> _openContact(String contactId) async {
    final contact = await DBHelper().getContactById(contactId);
    if (!mounted || contact == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ContactDetailsPage(
          contact: contact,
          onDelete: () async {},
        ),
      ),
    );
  }

  Future<void> _confirmSuggestion(StageSuggestion suggestion) async {
    await ContactStageService().confirmSuggestion(
      suggestion.contactId,
      suggestion.to,
    );
    if (!mounted) return;
    CrispToast.show(
      context,
      '${suggestion.name} → ${suggestion.to}',
    );
    await _load();
  }

  Future<void> _dismissSuggestion(StageSuggestion suggestion) async {
    await ContactStageService().dismissSuggestion(
      suggestion.contactId,
      suggestion.to,
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Review',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 26,
              letterSpacing: -0.52,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _data;
    if (data == null) {
      return const Center(child: Text('Unable to load review.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildPeriodChips(data),
          _buildPeriodHeading(data),
          _buildVerdictCard(data),
          _buildMovementCard(data),
          _buildSuggestions(data),
          _buildMarks(data),
          _buildIntentionCard(data),
          _buildCare(data),
          _buildEffort(data),
          _buildAbsent(data),
        ],
      ),
    );
  }

  Widget _buildPeriodChips(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Row(
        children: [
          for (final period in ReviewPeriod.values) ...[
            if (period != ReviewPeriod.values.first) const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => _selectPeriod(period),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: period == _period
                        ? colorScheme.onSurface
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: period == _period
                          ? colorScheme.onSurface
                          : colorScheme.cardBorder,
                    ),
                  ),
                  child: Text(
                    period.chip,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: period == _period
                          ? colorScheme.surface
                          : colorScheme.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodHeading(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            data.periodLabel,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.4,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            data.periodRange,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerdictCard(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color bg, Color border, Color dot) = switch (data.verdictKind) {
      ReviewMarkKind.attention => (
          colorScheme.dangerTint2,
          colorScheme.dangerBorder,
          colorScheme.error,
        ),
      ReviewMarkKind.watch => (
          colorScheme.surfaceTint,
          Colors.transparent,
          colorScheme.outline,
        ),
      ReviewMarkKind.bright => (
          colorScheme.greenTint,
          Colors.transparent,
          colorScheme.primary,
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  data.verdictLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: dot,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              data.verdict,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.35,
                letterSpacing: -0.3,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementCard(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    Color resolve(ColorLike color) =>
        brightness == Brightness.light ? Color(color.light) : Color(color.dark);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Movement',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  data.moveSummary,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final entry in data.funnel) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (entry.note != null) ...[
                          const SizedBox(width: 7),
                          Text(
                            entry.note!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${entry.count}',
                          style: TextStyle(
                            color: colorScheme.outline,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: entry.fraction,
                        minHeight: 9,
                        backgroundColor: colorScheme.surfaceTint,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(resolve(entry.color)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (data.hasMoves) ...[
              Container(
                height: 1,
                color: colorScheme.cardBorder,
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
              const SizedBox(height: 8),
              for (final t in data.transitions)
                InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => _openContact(t.contactId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 31,
                          height: 31,
                          decoration: BoxDecoration(
                            color: colorScheme.greenTint,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            t.initials,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                t.path,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.greenTint,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            t.forward ? 'Forward' : 'Back',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ] else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.dangerTint2,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: colorScheme.dangerBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      data.noMovesTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Open a contact and log an interaction the moment someone '
                      'takes a step.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(PeriodReviewData data) {
    if (data.suggestions.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.primary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 17,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Confirm stage changes',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Inferred from what you logged. Nothing counts until you '
              'confirm it.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            for (final suggestion in data.suggestions) ...[
              Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colorScheme.hairline),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colorScheme.greenTint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            suggestion.initials,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                suggestion.path,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      suggestion.why,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => _confirmSuggestion(suggestion),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                'Confirm',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => _dismissSuggestion(suggestion),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceTint,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                'Not yet',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.secondaryText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMarks(PeriodReviewData data) {
    if (data.marks.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Marks',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 11),
          for (final mark in data.marks) ...[
            _MarkCard(mark: mark),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildIntentionCard(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color color, double pct) = switch (data.intentionKind) {
      ReviewMarkKind.bright => (colorScheme.primary, data.intentionPct),
      ReviewMarkKind.watch => (const Color(0xFFC08A3F), data.intentionPct),
      ReviewMarkKind.attention => (colorScheme.error, data.intentionPct),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Intention',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${data.intentionGot} of ${data.intentionGoal}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              data.intentionText,
              style: TextStyle(
                fontSize: 13.5,
                color: colorScheme.secondaryText,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: colorScheme.surfaceTint,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCare(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Care',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 11),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 2.1,
            children: [
              for (final tile in data.care) _CareTile(tile: tile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEffort(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Effort',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'vs ${data.prevLabel}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in data.effort)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.hairline),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${row.value}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _DeltaChip(delta: row.delta),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAbsent(PeriodReviewData data) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What didn\'t happen',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'The quiet part, written down.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 9),
          for (final text in data.absent)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.hairline),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.close,
                    size: 16,
                    color: colorScheme.faint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkCard extends StatelessWidget {
  const _MarkCard({required this.mark});

  final ReviewMark mark;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color bg, Color border, Color dot, Color labelColor) =
        switch (mark.kind) {
      ReviewMarkKind.attention => (
          colorScheme.dangerTint2,
          colorScheme.dangerBorder,
          colorScheme.error,
          colorScheme.error,
        ),
      ReviewMarkKind.watch => (
          colorScheme.surfaceTint,
          Colors.transparent,
          colorScheme.outline,
          colorScheme.outline,
        ),
      ReviewMarkKind.bright => (
          colorScheme.greenTint,
          Colors.transparent,
          colorScheme.primary,
          colorScheme.primary,
        ),
    };
    final label = switch (mark.kind) {
      ReviewMarkKind.attention => 'Attention',
      ReviewMarkKind.watch => 'Watch',
      ReviewMarkKind.bright => 'Bright spot',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.95,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mark.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.3,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mark.detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.secondaryText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CareTile extends StatelessWidget {
  const _CareTile({required this.tile});

  final ReviewCareTile tile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tile.bad ? colorScheme.dangerTint2 : colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: tile.bad ? colorScheme.dangerBorder : colorScheme.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tile.value,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -0.675,
              color: tile.bad ? colorScheme.error : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            tile.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.secondaryText,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta});

  final int delta;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color color, Color bg) = delta > 0
        ? (colorScheme.primary, colorScheme.greenTint)
        : delta < 0
            ? (colorScheme.error, colorScheme.dangerTint)
            : (colorScheme.outline, colorScheme.surfaceTint);
    final label = delta > 0
        ? '+$delta'
        : delta < 0
            ? '$delta'
            : '0';
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
