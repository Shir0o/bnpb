import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/analytics_repository.dart';

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

class _AnalyticsPageState extends State<AnalyticsPage> {
  final AnalyticsRepository _repository = AnalyticsRepository();
  final DateFormat _dateLabelFormatter = DateFormat.yMMMd();

  AnalyticsSummary? _summary;
  bool _isLoading = true;
  AnalyticsRange _selectedRange = AnalyticsRange.last30Days;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
    });

    final now = DateTime.now();
    final start = _startForRange(_selectedRange, now);
    final summary = await _repository.buildSummary(
      rangeStart: start,
      rangeEnd: now,
    );

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AnalyticsRange>(
                value: _selectedRange,
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
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final summary = _summary;
    if (summary == null) {
      return const Center(child: Text('Unable to load analytics.'));
    }

    return RefreshIndicator(
      onRefresh: _loadSummary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeadlineCard(summary),
          const SizedBox(height: 16),
          _buildTopContactsCard(summary),
          const SizedBox(height: 16),
          _buildCategoryCard(summary),
          const SizedBox(height: 16),
          _buildTimelineCard(summary),
          const SizedBox(height: 16),
          _buildAttendanceTrendCard(summary),
          const SizedBox(height: 16),
          _buildAttendanceEngagementCard(summary),
          const SizedBox(height: 16),
          _buildGapCard(summary),
        ],
      ),
    );
  }

  Widget _buildHeadlineCard(AnalyticsSummary summary) {
    final rangeText = _describeRange(summary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rangeText,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Interactions',
                    value: summary.totalInteractions.toString(),
                    icon: Icons.forum_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _MetricTile(
                    label: 'Minutes invested',
                    value: summary.totalMinutes.toString(),
                    icon: Icons.timer_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _MetricTile(
                    label: 'Avg attendance',
                    value: _formatPercentage(summary.averageAttendanceRate),
                    icon: Icons.event_available_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
        .map((entry) => _resolveValue(entry.totalMinutes, entry.interactionCount))
        .toList();
    final maxY = values.reduce(math.max);
    final double yInterval =
        (maxY == 0 ? 1 : math.max(1, maxY / 4)).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top contacts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: entries.asMap().entries.map((entry) {
                    final index = entry.key;
                    final value = values[index];
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: value,
                          width: 18,
                          borderRadius: BorderRadius.circular(6),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 72,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Transform.rotate(
                              angle: -math.pi / 4,
                              child: SizedBox(
                                width: 80,
                                child: Text(
                                  entries[index].contactName,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...entries.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(entry.contactName),
                subtitle: Text(
                  '${entry.interactionCount} interaction${entry.interactionCount == 1 ? '' : 's'}',
                ),
                trailing: Text(
                  entry.totalMinutes > 0
                      ? '${entry.totalMinutes} min'
                      : '${entry.interactionCount} logs',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(AnalyticsSummary summary) {
    final entries = summary.categoryBreakdown.where((entry) {
      return entry.interactionCount > 0;
    }).take(6).toList();

    if (entries.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Time by category',
        message: 'Add categories to your interactions to compare focus areas.',
      );
    }

    final totalValue = entries.fold<double>(
      0,
      (value, entry) => value +
          _resolveValue(entry.totalMinutes, entry.interactionCount),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Time by category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final biggest = constraints.biggest;
                  final shortestSide =
                      math.min(biggest.width, biggest.height);
                  final sectionRadius = math.max(
                    0,
                    (shortestSide / 2) - 8,
                  ); // avoid overflow
                  final centerSpaceRadius = sectionRadius / 2;

                  return PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: centerSpaceRadius,
                      sections: entries.asMap().entries.map((entry) {
                        final value = _resolveValue(
                          entry.value.totalMinutes,
                          entry.value.interactionCount,
                        );
                        final percentage =
                            totalValue == 0 ? 0 : (value / totalValue) * 100;
                        return PieChartSectionData(
                          value: value,
                          title: '${percentage.toStringAsFixed(1)}%',
                          radius: sectionRadius,
                          titleStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entries.map((entry) {
                final label = entry.totalMinutes > 0
                    ? '${entry.category} • ${entry.totalMinutes} min'
                    : '${entry.category} • ${entry.interactionCount} logs';
                return Chip(
                  avatar: const Icon(Icons.label_outline, size: 18),
                  label: Text(label),
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
        title: 'Time series',
        message: 'Log interactions to populate the activity trend.',
      );
    }

    final values = timeline
        .map((entry) => _resolveValue(entry.totalMinutes, entry.interactionCount))
        .toList();
    final maxY = values.reduce(math.max);
    final double yInterval =
        (maxY == 0 ? 1 : math.max(1, maxY / 4)).toDouble();
    final labelStep = math.min(timeline.length, math.max(1, (timeline.length / 6).ceil()));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity trend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 4,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color:
                            Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      ),
                      spots: timeline.asMap().entries.map((entry) {
                        final index = entry.key.toDouble();
                        final value = values[entry.key];
                        return FlSpot(index, value);
                      }).toList(),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= timeline.length) {
                            return const SizedBox.shrink();
                          }
                          if (index % labelStep != 0 && index != 0 && index != timeline.length - 1) {
                            return const SizedBox.shrink();
                          }
                          final date = timeline[index].date;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat.Md().format(date),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTrendCard(AnalyticsSummary summary) {
    final sessions = summary.sessionAttendance;
    if (sessions.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Attendance trend',
        message: 'Track attendance sessions to see participation over time.',
      );
    }

    final values = sessions
        .map((session) => (session.attendanceRate ?? 0) * 100)
        .toList();
    final maxY = math.max(100.0, values.reduce(math.max));
    final yInterval = math.max(10.0, maxY / 5);
    final labelStep =
        math.max(1, (sessions.length / 4).ceil());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance trend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 4,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.15),
                      ),
                      spots: sessions.asMap().entries.map((entry) {
                        final index = entry.key.toDouble();
                        final value = values[entry.key];
                        return FlSpot(index, value);
                      }).toList(),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= sessions.length) {
                            return const SizedBox.shrink();
                          }
                          if (index % labelStep != 0 &&
                              index != sessions.length - 1) {
                            return const SizedBox.shrink();
                          }
                          final session = sessions[index];
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat.Md().format(session.sessionDate),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceEngagementCard(AnalyticsSummary summary) {
    final contacts = summary.contactAttendance;
    if (contacts.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Attendance engagement',
        message: 'Log attendance entries to see who is most engaged.',
      );
    }

    final mostEngaged = contacts.take(3).toList();
    final excludedIds = mostEngaged.map((contact) => contact.contactId).toSet();
    final leastEngaged = contacts.reversed
        .where((contact) => !excludedIds.contains(contact.contactId))
        .take(3)
        .toList();

    Widget buildList(String title, List<ContactAttendanceSnapshot> items) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.map((item) {
              final subtitle =
                  '${item.presentCount} of ${item.totalCount} sessions';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(item.contactName),
                subtitle: Text(subtitle),
                trailing: Text(_formatPercentage(item.attendanceRate)),
              );
            }),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance engagement',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                buildList('Most engaged', mostEngaged),
                const SizedBox(width: 16),
                buildList('Needs attention', leastEngaged),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGapCard(AnalyticsSummary summary) {
    final gaps = summary.contactGaps.take(6).toList();
    if (gaps.isEmpty) {
      return const _EmptyAnalyticsCard(
        title: 'Follow-up reminders',
        message: 'Add interactions to identify contacts that need attention.',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Follow-up reminders',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...gaps.map((gap) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  gap.hasNeverInteracted
                      ? Icons.new_releases_outlined
                      : Icons.hourglass_bottom,
                ),
                title: Text(gap.contactName),
                subtitle: Text(
                  gap.hasNeverInteracted
                      ? 'No interactions logged yet'
                      : 'Last contact ${_dateLabelFormatter.format(gap.lastInteractionAt!)}',
                ),
                trailing: Text(_formatGap(gap.gap)),
              );
            }).toList(),
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

  String _formatPercentage(double? rate) {
    if (rate == null) {
      return '—';
    }
    return '${(rate * 100).toStringAsFixed(0)}%';
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
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _EmptyAnalyticsCard extends StatelessWidget {
  const _EmptyAnalyticsCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
