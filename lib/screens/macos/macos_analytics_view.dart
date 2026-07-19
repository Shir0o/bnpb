import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show CrispColorScheme;
import '../../repositories/analytics_repository.dart';
import '../../repositories/relationship_insights_repository.dart';

enum _Range { last30, last90, last365, all }

extension on _Range {
  String get label {
    switch (this) {
      case _Range.last30:
        return 'Last 30 days';
      case _Range.last90:
        return 'Last 90 days';
      case _Range.last365:
        return 'Last year';
      case _Range.all:
        return 'All time';
    }
  }
}

const String _dismissedInsightsPrefKey = 'analytics.insights.dismissed';

/// Desktop "Analytics" section: a full-width dashboard grid, ported from the
/// mobile `AnalyticsPage`'s repositories/chart logic.
class MacOSAnalyticsView extends StatefulWidget {
  const MacOSAnalyticsView({super.key});

  @override
  State<MacOSAnalyticsView> createState() => _MacOSAnalyticsViewState();
}

class _MacOSAnalyticsViewState extends State<MacOSAnalyticsView> {
  final AnalyticsRepository _repository = AnalyticsRepository();
  final RelationshipInsightsRepository _insightsRepository =
      RelationshipInsightsRepository();
  final DateFormat _timelineLabelFormatter = DateFormat.Md();

  AnalyticsSummary? _summary;
  List<RelationshipInsight> _insights = const [];
  Set<String> _dismissedInsightIds = const {};
  bool _isLoading = true;
  _Range _range = _Range.last30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _startForRange(_Range range, DateTime now) {
    switch (range) {
      case _Range.last30:
        return now.subtract(const Duration(days: 30));
      case _Range.last90:
        return now.subtract(const Duration(days: 90));
      case _Range.last365:
        return now.subtract(const Duration(days: 365));
      case _Range.all:
        return null;
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final start = _startForRange(_range, now);
    try {
      final results = await Future.wait([
        _repository.buildSummary(rangeStart: start, rangeEnd: now),
        _insightsRepository.buildInsights(),
        SharedPreferences.getInstance().then(
          (prefs) =>
              prefs.getStringList(_dismissedInsightsPrefKey)?.toSet() ??
              <String>{},
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as AnalyticsSummary;
        _insights = results[1] as List<RelationshipInsight>;
        _dismissedInsightIds = results[2] as Set<String>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summary = null;
        _insights = const [];
        _isLoading = false;
      });
    }
  }

  Future<void> _dismissInsight(String id) async {
    final updated = {..._dismissedInsightIds, id};
    setState(() => _dismissedInsightIds = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedInsightsPrefKey, updated.toList());
  }

  double _resolveValue(int minutes, int interactions) =>
      minutes > 0 ? minutes.toDouble() : interactions.toDouble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(34, 26, 34, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Analytics',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 27,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      _buildRangePicker(colorScheme),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildGrid(colorScheme),
                ],
              ),
            ),
    );
  }

  Widget _buildRangePicker(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_Range>(
          value: _range,
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16, color: colorScheme.onSurface),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _range = value);
            _load();
          },
          items: _Range.values
              .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildGrid(ColorScheme colorScheme) {
    final summary = _summary;
    if (summary == null) {
      return Text(
        'Could not load analytics.',
        style: TextStyle(color: colorScheme.error),
      );
    }

    final visibleInsights = _insights
        .where((i) =>
            !_dismissedInsightIds.contains(i.id) &&
            (i.type == RelationshipInsightType.driftingContact ||
                i.type == RelationshipInsightType.silenceStreak))
        .take(6)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.7,
          children: [
            _headlineCard(
              colorScheme,
              icon: Icons.forum_outlined,
              value: '${summary.totalInteractions}',
              label: 'Interactions logged',
              dark: true,
            ),
            _headlineCard(
              colorScheme,
              icon: Icons.timer_outlined,
              value: '${summary.totalMinutes}',
              label: 'Minutes invested',
              dark: false,
            ),
            _topContactsCard(colorScheme, summary),
            _timelineCard(colorScheme, summary),
          ],
        ),
        if (visibleInsights.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Relationship insights',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3.6,
            children: visibleInsights
                .map((i) => _insightCard(colorScheme, i))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _headlineCard(
    ColorScheme colorScheme, {
    required IconData icon,
    required String value,
    required String label,
    required bool dark,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? colorScheme.aiCardBg : colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 24, color: dark ? const Color(0xFF5FE0A0) : Colors.white),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: dark ? const Color(0xFF94A49B) : const Color(0xFFBFE6D1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topContactsCard(ColorScheme colorScheme, AnalyticsSummary summary) {
    final entries = summary.contactInvestments.take(5).toList();
    if (entries.isEmpty) {
      return _emptyCard(
          colorScheme, 'Top contacts', 'No interactions in this range yet.');
    }
    final values = entries
        .map((e) => _resolveValue(e.totalMinutes, e.interactionCount))
        .toList();
    final maxY = values.reduce(math.max);
    final barColors = [
      colorScheme.primary,
      const Color(0xFF2AA06E),
      const Color(0xFF7FC7A6),
      const Color(0xFFA9DCC4),
      const Color(0xFFCDEADD),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top contacts',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RepaintBoundary(
              child: BarChart(
                BarChartData(
                  maxY: maxY == 0 ? 1 : maxY * 1.1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: entries.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: values[e.key],
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          color: barColors[e.key % barColors.length],
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: const FlTitlesData(
                    leftTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...entries.asMap().entries.map((e) {
            final c = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: barColors[e.key % barColors.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.contactName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    c.totalMinutes > 0
                        ? '${c.totalMinutes} min'
                        : '${c.interactionCount} logs',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _timelineCard(ColorScheme colorScheme, AnalyticsSummary summary) {
    final timeline = summary.timeline;
    if (timeline.isEmpty) {
      return _emptyCard(
          colorScheme, 'Activity trend', 'Log interactions to see a trend.');
    }
    final values = timeline
        .map((e) => _resolveValue(e.totalMinutes, e.interactionCount))
        .toList();
    final maxY = values.reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity trend',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
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
                      spots: timeline.asMap().entries.map((e) {
                        return FlSpot(e.key.toDouble(), values[e.key]);
                      }).toList(),
                    ),
                  ],
                  titlesData: const FlTitlesData(
                    leftTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                    color: colorScheme.outline),
              ),
              Text(
                _timelineLabelFormatter.format(timeline.last.date),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _insightCard(ColorScheme colorScheme, RelationshipInsight insight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.dangerBorder),
        color: colorScheme.dangerTint2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_down, size: 20, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  insight.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (insight.phrasing != null)
                  Text(
                    insight.phrasing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: colorScheme.error),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _dismissInsight(insight.id),
            child: Icon(Icons.close,
                size: 16, color: colorScheme.error.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(ColorScheme colorScheme, String title, String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(fontSize: 13, color: colorScheme.outline)),
        ],
      ),
    );
  }
}
