import '../db/db_helper.dart';

import '../models/contact.dart';
import '../models/interaction.dart';

/// Aggregated analytics describing how much time has been invested with a
/// contact.
class ContactTimeInvestment {
  const ContactTimeInvestment({
    required this.contactId,
    required this.contactName,
    required this.totalMinutes,
    required this.interactionCount,
  });

  final String contactId;
  final String contactName;
  final int totalMinutes;
  final int interactionCount;
}

/// Aggregated analytics describing time invested for a given category label.
class CategoryBreakdownEntry {
  const CategoryBreakdownEntry({
    required this.category,
    required this.totalMinutes,
    required this.interactionCount,
  });

  final String category;
  final int totalMinutes;
  final int interactionCount;
}

/// Aggregated analytics for a specific day.
class TimeSeriesPoint {
  const TimeSeriesPoint({
    required this.date,
    required this.totalMinutes,
    required this.interactionCount,
  });

  final DateTime date;
  final int totalMinutes;
  final int interactionCount;
}

/// Attendance rate information for a single session.

/// Summary describing the gap since the last time a contact was reached out to.
class ContactGap {
  const ContactGap({
    required this.contactId,
    required this.contactName,
    required this.totalInteractions,
    required this.lastInteractionAt,
    required this.gap,
  });

  final String contactId;
  final String contactName;
  final int totalInteractions;
  final DateTime? lastInteractionAt;
  final Duration? gap;

  bool get hasNeverInteracted => lastInteractionAt == null;
}

/// Overall analytics summary that can be rendered in dashboards or charts.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.rangeStart,
    required this.rangeEnd,
    required this.totalInteractions,
    required this.totalMinutes,
    required this.contactInvestments,
    required this.categoryBreakdown,
    required this.timeline,
    required this.contactGaps,
  });

  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int totalInteractions;
  final int totalMinutes;
  final List<ContactTimeInvestment> contactInvestments;
  final List<CategoryBreakdownEntry> categoryBreakdown;
  final List<TimeSeriesPoint> timeline;
  final List<ContactGap> contactGaps;
}

/// Provides a higher-level analytic view over stored contacts and
/// interactions, including date range, category, and per-contact summaries.
class AnalyticsRepository {
  AnalyticsRepository({DBHelper? dbHelper})
      : _dbHelper = dbHelper ?? DBHelper();

  final DBHelper _dbHelper;

  Future<AnalyticsSummary> buildSummary({
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    final List<Contact> contacts = await _dbHelper.getContacts();
    final contactNameById = {
      for (final contact in contacts) contact.id: contact.fullName,
    };

    final now = DateTime.now();
    final contactAccumulators = <String, _ContactAccumulator>{};
    final categoryAccumulators = <String, _CategoryAccumulator>{};
    final timelineAccumulators = <DateTime, _TimelineAccumulator>{};
    final contactGaps = <ContactGap>[];

    for (final Contact contact in contacts) {
      final accumulator = contactAccumulators.putIfAbsent(
        contact.id,
        () => _ContactAccumulator(contact.id, contact.fullName),
      );

      DateTime? latestInteraction;

      for (final Interaction interaction in contact.interactions) {
        final occurredAt = interaction.occurredAt;
        if (!_isWithinRange(occurredAt, rangeStart, rangeEnd)) {
          if (latestInteraction == null ||
              occurredAt.isAfter(latestInteraction)) {
            latestInteraction = occurredAt;
          }
          continue;
        }

        final durationMinutes = interaction.durationMinutes ?? 0;

        accumulator.totalMinutes += durationMinutes;
        accumulator.interactionCount += 1;

        final rawCategory = interaction.category?.trim();
        final categoryKey = (rawCategory == null || rawCategory.isEmpty)
            ? 'Uncategorized'
            : rawCategory;
        final categoryAccumulator = categoryAccumulators.putIfAbsent(
          categoryKey,
          () => _CategoryAccumulator(categoryKey),
        );
        categoryAccumulator.totalMinutes += durationMinutes;
        categoryAccumulator.interactionCount += 1;

        final bucket =
            DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
        final timelineAccumulator = timelineAccumulators.putIfAbsent(
          bucket,
          () => _TimelineAccumulator(bucket),
        );
        timelineAccumulator.totalMinutes += durationMinutes;
        timelineAccumulator.interactionCount += 1;

        if (latestInteraction == null ||
            occurredAt.isAfter(latestInteraction)) {
          latestInteraction = occurredAt;
        }
      }

      contactGaps.add(
        ContactGap(
          contactId: contact.id,
          contactName: contact.fullName,
          totalInteractions: contact.interactions.length,
          lastInteractionAt: latestInteraction,
          gap: latestInteraction != null
              ? now.difference(latestInteraction)
              : null,
        ),
      );
    }

    final contactInvestments =
        contactAccumulators.values.map((entry) => entry.toDomain()).toList()
          ..sort((a, b) {
            final durationCompare = b.totalMinutes.compareTo(a.totalMinutes);
            if (durationCompare != 0) {
              return durationCompare;
            }
            return b.interactionCount.compareTo(a.interactionCount);
          });

    final categoryBreakdown =
        categoryAccumulators.values.map((entry) => entry.toDomain()).toList()
          ..sort((a, b) {
            final durationCompare = b.totalMinutes.compareTo(a.totalMinutes);
            if (durationCompare != 0) {
              return durationCompare;
            }
            return b.interactionCount.compareTo(a.interactionCount);
          });

    final timeline = timelineAccumulators.values
        .map((entry) => entry.toDomain())
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    contactGaps.sort((a, b) {
      final aGap = a.gap?.inSeconds.toDouble() ?? double.infinity;
      final bGap = b.gap?.inSeconds.toDouble() ?? double.infinity;
      final comparison = bGap.compareTo(aGap);
      if (comparison != 0) {
        return comparison;
      }
      return a.contactName.toLowerCase().compareTo(b.contactName.toLowerCase());
    });

    final totalMinutes = contactInvestments.fold<int>(
      0,
      (previousValue, element) => previousValue + element.totalMinutes,
    );
    final totalInteractions = contactInvestments.fold<int>(
      0,
      (previousValue, element) => previousValue + element.interactionCount,
    );

    return AnalyticsSummary(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      totalInteractions: totalInteractions,
      totalMinutes: totalMinutes,
      contactInvestments: contactInvestments,
      categoryBreakdown: categoryBreakdown,
      timeline: timeline,
      contactGaps: contactGaps,
    );
  }

  bool _isWithinRange(DateTime value, DateTime? start, DateTime? end) {
    if (start != null && value.isBefore(start)) {
      return false;
    }
    if (end != null && value.isAfter(end)) {
      return false;
    }
    return true;
  }
}

class _ContactAccumulator {
  _ContactAccumulator(this.contactId, this.contactName);

  final String contactId;
  final String contactName;
  int totalMinutes = 0;
  int interactionCount = 0;

  ContactTimeInvestment toDomain() {
    return ContactTimeInvestment(
      contactId: contactId,
      contactName: contactName,
      totalMinutes: totalMinutes,
      interactionCount: interactionCount,
    );
  }
}

class _CategoryAccumulator {
  _CategoryAccumulator(this.category);

  final String category;
  int totalMinutes = 0;
  int interactionCount = 0;

  CategoryBreakdownEntry toDomain() {
    return CategoryBreakdownEntry(
      category: category,
      totalMinutes: totalMinutes,
      interactionCount: interactionCount,
    );
  }
}

class _TimelineAccumulator {
  _TimelineAccumulator(this.date);

  final DateTime date;
  int totalMinutes = 0;
  int interactionCount = 0;

  TimeSeriesPoint toDomain() {
    return TimeSeriesPoint(
      date: date,
      totalMinutes: totalMinutes,
      interactionCount: interactionCount,
    );
  }
}
