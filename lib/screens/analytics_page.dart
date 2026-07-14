import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show CrispColorScheme;
import '../repositories/analytics_repository.dart';
import '../repositories/relationship_insights_repository.dart';
import '../services/ai/ai_services.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/hide_on_scroll_scaffold.dart';
import 'ask_page.dart';

/// Predefined ranges supported by the analytics dashboard.
enum AnalyticsRange { last30Days, last90Days, last365Days, allTime }

extension on AnalyticsRange {
  String get label {
    switch (this) {
      case AnalyticsRange.last30Days:
        return '30 days';
      case AnalyticsRange.last90Days:
        return '90 days';
      case AnalyticsRange.last365Days:
        return '1 year';
      case AnalyticsRange.allTime:
        return 'All time';
    }
  }
}

/// Surface-level analytics summarizing interactions and focus areas.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with AutomaticKeepAliveClientMixin {
  final AnalyticsRepository _repository = AnalyticsRepository();
  final RelationshipInsightsRepository _insightsRepository =
      RelationshipInsightsRepository();
  late final DateFormat _dateLabelFormatter;
  late final DateFormat _timelineLabelFormatter;

  AnalyticsSummary? _summary;
  List<RelationshipInsight> _insights = const [];
  Set<String> _dismissedInsightIds = const {};
  bool _isLoading = true;
  AnalyticsRange _selectedRange = AnalyticsRange.last30Days;

  static const String _dismissedInsightsPrefKey =
      'analytics.insights.dismissed';

  @override
  void initState() {
    super.initState();
    _dateLabelFormatter = DateFormat.yMMMd();
    _timelineLabelFormatter = DateFormat.Md();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
    });
    final stopwatch = Stopwatch()..start();

    final now = DateTime.now();
    final start = _startForRange(_selectedRange, now);
    List<Object>? results;
    try {
      results = await Future.wait([
        _repository.buildSummary(rangeStart: start, rangeEnd: now),
        _insightsRepository.buildInsights(),
        SharedPreferences.getInstance().then(
          (prefs) =>
              prefs.getStringList(_dismissedInsightsPrefKey)?.toSet() ??
              <String>{},
        ),
      ]);
    } catch (_) {
      // Surface the error state instead of leaving the page spinning.
    }

    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 300) {
      await Future.delayed(Duration(milliseconds: 300 - elapsed));
    }

    if (!mounted) return;
    setState(() {
      if (results != null) {
        _summary = results[0] as AnalyticsSummary;
        _insights = results[1] as List<RelationshipInsight>;
        _dismissedInsightIds = results[2] as Set<String>;
      } else {
        _summary = null;
        _insights = const [];
      }
      _isLoading = false;
    });
  }

  Future<void> _dismissInsight(String id) async {
    final updated = {..._dismissedInsightIds, id};
    setState(() {
      _dismissedInsightIds = updated;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedInsightsPrefKey, updated.toList());
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 390;
    final double titleSize = isSmallScreen ? 26.0 : 34.0;

    return HideOnScrollScaffold(
      appBar: AppBar(
        title: Text(
          'Analytics',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.6,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 22.0),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.surfaceTint,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AnalyticsRange>(
                  value: _selectedRange,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurface,
                    size: 18,
                  ),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedRange = value;
                    });
                    _loadSummary();
                  },
                  items: AnalyticsRange.values
                      .map(
                        (range) => DropdownMenuItem(
                          value: range,
                          child: Text(range.label),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _AnalyticsSkeleton(key: ValueKey('loading'));
    }

    final summary = _summary;
    if (summary == null) {
      return const Center(
        key: ValueKey('error'),
        child: Text('Unable to load analytics.'),
      );
    }

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _loadSummary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        children: [
          _buildHeadlineCard(summary),
          const SizedBox(height: 16),
          if (AiServices().embedding.isReady) ...[
            _buildAskCard(),
            const SizedBox(height: 16),
          ],
          ..._buildInsightCards(),
          _buildTopContactsCard(summary),
          const SizedBox(height: 16),
          _buildCategoryCard(summary),
          const SizedBox(height: 16),
          _buildTimelineCard(summary),
          const SizedBox(height: 16),
          _buildGapCard(summary),
        ],
      ),
    );
  }

  List<Widget> _buildInsightCards() {
    final visible =
        _insights.where((i) => !_dismissedInsightIds.contains(i.id)).toList();
    if (visible.isEmpty) return const [];
    return [
      Text(
        'Relationship insights',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      ...visible.map(
        (insight) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _InsightCard(
            insight: insight,
            subtitle: _insightSubtitle(insight),
            onDismiss: () => _dismissInsight(insight.id),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ];
  }

  String _insightSubtitle(RelationshipInsight insight) {
    final details = insight.details ?? const {};
    switch (insight.type) {
      case RelationshipInsightType.driftingContact:
        final median = details['medianGapDays'];
        final current = details['currentGapDays'];
        return 'Usually every $median day${median == 1 ? '' : 's'}, '
            'silent for $current.';
      case RelationshipInsightType.silenceStreak:
        return '${details['gapDays']} days since the last interaction.';
      case RelationshipInsightType.stalePrayerRequests:
        return '${details['pendingCount']} pending, oldest '
            '${details['oldestDays']} days old.';
      case RelationshipInsightType.answeredPrayer:
        final raw = (details['description'] as String?)?.trim() ?? '';
        if (raw.isEmpty) return 'Answered recently.';
        return raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
      case RelationshipInsightType.followUpCompletionRate:
        return '${details['completed']} of ${details['totalDue']} past '
            'follow-ups had a later interaction.';
    }
  }

  Widget _buildAskCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AskPage()));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.search_outlined,
                  color: colorScheme.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask about your contacts',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Semantic search, fully on-device',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colorScheme.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeadlineCard(AnalyticsSummary summary) {
    final rangeText = _describeRange(summary);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            rangeText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Interactions',
                value: summary.totalInteractions.toString(),
                icon: Icons.chat_bubble_outline_rounded,
                // Fixed near-black tile (matches --ai-card) with fixed
                // white/accent contents in both themes, per the design.
                backgroundColor: colorScheme.aiCardBg,
                valueColor: Colors.white,
                labelColor: const Color(0xFF94A49B),
                iconColor: const Color(0xFF5FE0A0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Minutes invested',
                value: summary.totalMinutes.toString(),
                icon: Icons.timer_outlined,
                backgroundColor: colorScheme.primary,
                valueColor: Colors.white,
                labelColor: const Color(0xFFBFE6D1),
                iconColor: const Color(0xFFC7F0DA),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopContactsCard(AnalyticsSummary summary) {
    final entries = summary.contactInvestments.take(5).toList();
    if (entries.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Top contacts',
        message: 'No interactions recorded in this range yet.',
      );
    }

    final values = entries
        .map(
          (entry) => _resolveValue(entry.totalMinutes, entry.interactionCount),
        )
        .toList();
    final maxY = values.reduce(math.max);

    final colorScheme = Theme.of(context).colorScheme;
    // First bar mirrors the design's `var(--green)` (theme-reactive); the
    // rest are the design's own fixed decorative gradient, unrelated to a
    // CSS token.
    final List<Color> barColors = [
      colorScheme.primary,
      const Color(0xFF2AA06E),
      const Color(0xFF7FC7A6),
      const Color(0xFFA9DCC4),
      const Color(0xFFCDEADD),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top contacts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 130,
              child: RepaintBoundary(
                child: BarChart(
                  BarChartData(
                    maxY: maxY == 0 ? 1 : maxY * 1.1,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: entries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final value = values[index];
                      final color = barColors[index % barColors.length];
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: value,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                            color: color,
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              height: 1,
              color: colorScheme.surfaceContainerHighest,
              margin: const EdgeInsets.symmetric(vertical: 12),
            ),
            ...entries.asMap().entries.map((entry) {
              final index = entry.key;
              final contact = entry.value;
              final color = barColors[index % barColors.length];
              final statText = contact.totalMinutes > 0
                  ? '${contact.interactionCount} · ${contact.totalMinutes} min'
                  : '${contact.interactionCount} logs';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        contact.contactName,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      statText,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(AnalyticsSummary summary) {
    final entries = summary.categoryBreakdown
        .where((entry) => entry.interactionCount > 0)
        .take(6)
        .toList();

    if (entries.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Prayer focus areas',
        message: 'Add categories to your prayer requests to see a breakdown.',
      );
    }

    final totalValue = entries.fold<double>(
      0,
      (value, entry) =>
          value + _resolveValue(entry.totalMinutes, entry.interactionCount),
    );

    final colorScheme = Theme.of(context).colorScheme;
    // First section mirrors the design's `var(--green)` (theme-reactive);
    // the rest are the design's own fixed decorative gradient.
    final List<Color> sectionColors = [
      colorScheme.primary,
      const Color(0xFF2AA06E),
      const Color(0xFF7FC7A6),
      const Color(0xFFA9DCC4),
      const Color(0xFFCDEADD),
      const Color(0xFF127A6B),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prayer focus areas',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final biggest = constraints.biggest;
                  final shortestSide = math.min(biggest.width, biggest.height);
                  final double maxRadius = (shortestSide / 2) - 8;
                  final double sectionRadius = math.max(0.0, maxRadius / 1.5);
                  final centerSpaceRadius = sectionRadius / 2;

                  return RepaintBoundary(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: centerSpaceRadius,
                        sections: entries.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final value = _resolveValue(
                            entry.value.totalMinutes,
                            entry.value.interactionCount,
                          );
                          final percentage =
                              totalValue == 0 ? 0 : (value / totalValue) * 100;
                          final color =
                              sectionColors[idx % sectionColors.length];
                          return PieChartSectionData(
                            value: value,
                            title: '${percentage.toStringAsFixed(1)}%',
                            radius: sectionRadius,
                            color: color,
                            titleStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimary,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entries.asMap().entries.map((entry) {
                final idx = entry.key;
                final color = sectionColors[idx % sectionColors.length];
                final label =
                    '${entry.value.category} • ${entry.value.interactionCount} request${entry.value.interactionCount == 1 ? '' : 's'}';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(AnalyticsSummary summary) {
    final timeline = summary.timeline;
    if (timeline.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Activity trend',
        message: 'Log interactions to populate the activity trend.',
      );
    }

    final values = timeline
        .map(
          (entry) => _resolveValue(entry.totalMinutes, entry.interactionCount),
        )
        .toList();
    final maxY = values.reduce(math.max);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity trend',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: RepaintBoundary(
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY == 0 ? 1 : maxY * 1.1,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: colorScheme.primary,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colorScheme.primary.withValues(alpha: 0.18),
                              colorScheme.primary.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        spots: timeline.asMap().entries.map((entry) {
                          final index = entry.key.toDouble();
                          final value = values[entry.key];
                          return FlSpot(index, value);
                        }).toList(),
                      ),
                    ],
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _timelineLabelFormatter.format(timeline.first.date),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.outline,
                  ),
                ),
                if (timeline.length > 2)
                  Text(
                    _timelineLabelFormatter.format(
                      timeline[timeline.length ~/ 2].date,
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.outline,
                    ),
                  ),
                Text(
                  _timelineLabelFormatter.format(timeline.last.date),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGapCard(AnalyticsSummary summary) {
    final gaps =
        summary.contactGaps.where((gap) => gap.hasFollowUp).take(6).toList();
    if (gaps.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Follow-up reminders',
        message: 'No pending follow-ups. Add a follow-up date when logging '
            'an interaction to see reminders here.',
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Follow-up reminders',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...gaps.map((gap) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      gap.hasNeverInteracted
                          ? Icons.new_releases_outlined
                          : Icons.hourglass_bottom_rounded,
                      color: gap.hasNeverInteracted
                          ? colorScheme.error
                          : colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gap.contactName,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            gap.hasNeverInteracted
                                ? 'No interactions logged yet'
                                : 'Last contact ${_dateLabelFormatter.format(gap.lastInteractionAt!)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatGap(gap.gap),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: gap.hasNeverInteracted
                            ? colorScheme.error
                            : colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _describeRange(AnalyticsSummary summary) {
    final start = summary.rangeStart;
    final end = summary.rangeEnd ?? DateTime.now();
    if (start == null) {
      return 'All time through ${_dateLabelFormatter.format(end)}';
    }
    return '${_dateLabelFormatter.format(start)} – ${_dateLabelFormatter.format(end)}';
  }

  double _resolveValue(int minutes, int interactions) {
    if (minutes > 0) {
      return minutes.toDouble();
    }
    return interactions.toDouble();
  }

  String _formatGap(Duration? gap) {
    if (gap == null) {
      return '—';
    }
    if (gap.inDays >= 1) {
      return '${gap.inDays}d';
    }
    if (gap.inHours >= 1) {
      return '${gap.inHours}h';
    }
    return '${math.max(1, gap.inMinutes)}m';
  }

  DateTime? _startForRange(AnalyticsRange range, DateTime now) {
    switch (range) {
      case AnalyticsRange.last30Days:
        return now.subtract(const Duration(days: 30));
      case AnalyticsRange.last90Days:
        return now.subtract(const Duration(days: 90));
      case AnalyticsRange.last365Days:
        return now.subtract(const Duration(days: 365));
      case AnalyticsRange.allTime:
        return null;
    }
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.backgroundColor,
    required this.valueColor,
    required this.labelColor,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color backgroundColor;
  final Color valueColor;
  final Color labelColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: backgroundColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: valueColor,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAnalyticsCard extends StatelessWidget {
  const _EmptyAnalyticsCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.insight,
    required this.subtitle,
    required this.onDismiss,
  });

  final RelationshipInsight insight;
  final String subtitle;
  final VoidCallback onDismiss;

  IconData get _icon {
    switch (insight.type) {
      case RelationshipInsightType.driftingContact:
        return Icons.trending_down_rounded;
      case RelationshipInsightType.silenceStreak:
        return Icons.notifications_paused_outlined;
      case RelationshipInsightType.stalePrayerRequests:
        return Icons.event_note_outlined;
      case RelationshipInsightType.answeredPrayer:
        return Icons.celebration_outlined;
      case RelationshipInsightType.followUpCompletionRate:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final phrasing = insight.phrasing?.trim();

    final isDrifting =
        insight.type == RelationshipInsightType.driftingContact ||
            insight.type == RelationshipInsightType.silenceStreak ||
            insight.type == RelationshipInsightType.stalePrayerRequests;

    final cardBg = isDrifting
        ? colorScheme.dangerTint2
        : theme.cardTheme.color ?? colorScheme.surface;
    final borderColor = isDrifting
        ? colorScheme.dangerBorder
        : colorScheme.surfaceContainerHighest;
    final iconColor = isDrifting ? colorScheme.error : colorScheme.primary;
    final titleColor = colorScheme.onSurface;
    final subtitleColor =
        isDrifting ? const Color(0xFFA37060) : colorScheme.outline;
    final dismissColor =
        isDrifting ? const Color(0xFFD6B3A6) : colorScheme.outline;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: iconColor, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: subtitleColor,
                  ),
                ),
                if (phrasing != null && phrasing.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    phrasing,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: Icon(Icons.close, size: 16, color: dismissColor),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const SkeletonBox(height: 120), // Headline
          const SizedBox(height: 16),
          const SkeletonBox(height: 300), // Top contacts
          const SizedBox(height: 16),
          const SkeletonBox(height: 280), // Category card
          const SizedBox(height: 16),
          const SkeletonBox(height: 240), // Timeline
        ],
      ),
    );
  }
}
