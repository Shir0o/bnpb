import '../db/db_helper.dart';
import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';
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
class SessionAttendanceSnapshot {
  const SessionAttendanceSnapshot({
    required this.sessionId,
    required this.sessionTitle,
    required this.sessionDate,
    required this.presentCount,
    required this.totalCount,
  });

  final int sessionId;
  final String sessionTitle;
  final DateTime sessionDate;
  final int presentCount;
  final int totalCount;

  double? get attendanceRate {
    if (totalCount == 0) {
      return null;
    }
    return presentCount / totalCount;
  }
}

/// Attendance rate rollup for a contact across sessions.
class ContactAttendanceSnapshot {
  const ContactAttendanceSnapshot({
    required this.contactId,
    required this.contactName,
    required this.presentCount,
    required this.totalCount,
  });

  final String contactId;
  final String contactName;
  final int presentCount;
  final int totalCount;

  double? get attendanceRate {
    if (totalCount == 0) {
      return null;
    }
    return presentCount / totalCount;
  }
}

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
    required this.sessionAttendance,
    required this.contactAttendance,
    required this.averageAttendanceRate,
  });

  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int totalInteractions;
  final int totalMinutes;
  final List<ContactTimeInvestment> contactInvestments;
  final List<CategoryBreakdownEntry> categoryBreakdown;
  final List<TimeSeriesPoint> timeline;
  final List<ContactGap> contactGaps;
  final List<SessionAttendanceSnapshot> sessionAttendance;
  final List<ContactAttendanceSnapshot> contactAttendance;
  final double? averageAttendanceRate;
}

/// Provides a higher-level analytic view over stored contacts and
/// interactions, including date range, category, and per-contact summaries.
class AnalyticsRepository {
  AnalyticsRepository({DBHelper? dbHelper}) : _dbHelper = dbHelper ?? DBHelper();

  final DBHelper _dbHelper;

  Future<AnalyticsSummary> buildSummary({
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    final List<Contact> contacts = await _dbHelper.getContacts();
    final contactNameById = {
      for (final contact in contacts) contact.id: contact.fullName,
    };
    final sessions = await _dbHelper.getAttendanceSessions();
    final now = DateTime.now();

    final contactAccumulators = <String, _ContactAccumulator>{};
    final categoryAccumulators = <String, _CategoryAccumulator>{};
    final timelineAccumulators = <DateTime, _TimelineAccumulator>{};
    final contactGaps = <ContactGap>[];
    final sessionAttendance = <SessionAttendanceSnapshot>[];
    final contactAttendance = <String, _ContactAttendanceAccumulator>{};

    for (final Contact contact in contacts) {
      final accumulator = contactAccumulators.putIfAbsent(
        contact.id,
        () => _ContactAccumulator(contact.id, contact.fullName),
      );

      DateTime? latestInteraction;

      for (final Interaction interaction in contact.interactions) {
        final occurredAt = interaction.occurredAt;
        if (!_isWithinRange(occurredAt, rangeStart, rangeEnd)) {
          if (latestInteraction == null || occurredAt.isAfter(latestInteraction)) {
            latestInteraction = occurredAt;
          }
          continue;
        }

        final durationMinutes = interaction.durationMinutes ?? 0;

        accumulator.totalMinutes += durationMinutes;
        accumulator.interactionCount += 1;

        final rawCategory = interaction.category?.trim();
        final categoryKey =
            (rawCategory == null || rawCategory.isEmpty) ? 'Uncategorized' : rawCategory;
        final categoryAccumulator = categoryAccumulators.putIfAbsent(
          categoryKey,
          () => _CategoryAccumulator(categoryKey),
        );
        categoryAccumulator.totalMinutes += durationMinutes;
        categoryAccumulator.interactionCount += 1;

        final bucket = DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
        final timelineAccumulator = timelineAccumulators.putIfAbsent(
          bucket,
          () => _TimelineAccumulator(bucket),
        );
        timelineAccumulator.totalMinutes += durationMinutes;
        timelineAccumulator.interactionCount += 1;

        if (latestInteraction == null || occurredAt.isAfter(latestInteraction)) {
          latestInteraction = occurredAt;
        }
      }

      contactGaps.add(
        ContactGap(
          contactId: contact.id,
          contactName: contact.fullName,
          totalInteractions: contact.interactions.length,
          lastInteractionAt: latestInteraction,
          gap: latestInteraction != null ? now.difference(latestInteraction) : null,
        ),
      );
    }

    for (final AttendanceSession session in sessions) {
      if (!_isWithinRange(session.sessionDate, rangeStart, rangeEnd)) {
        continue;
      }

      if (session.id == null) {
        continue;
      }

      final entries = await _dbHelper.getAttendanceEntries(session.id!);
      final presentCount = entries
          .where((entry) => entry.status == AttendanceStatus.present)
          .length;
      final totalCount = entries.length;

      sessionAttendance.add(
        SessionAttendanceSnapshot(
          sessionId: session.id!,
          sessionTitle: session.title,
          sessionDate: session.sessionDate,
          presentCount: presentCount,
          totalCount: totalCount,
        ),
      );

      for (final entry in entries) {
        final contactName = contactNameById[entry.contactId] ?? 'Unknown contact';
        final accumulator = contactAttendance.putIfAbsent(
          entry.contactId,
          () => _ContactAttendanceAccumulator(entry.contactId, contactName),
        );

        accumulator.totalCount += 1;
        if (entry.status == AttendanceStatus.present) {
          accumulator.presentCount += 1;
        }
      }
    }

    final contactInvestments = contactAccumulators.values
        .map((entry) => entry.toDomain())
        .toList()
      ..sort((a, b) {
        final durationCompare = b.totalMinutes.compareTo(a.totalMinutes);
        if (durationCompare != 0) {
          return durationCompare;
        }
        return b.interactionCount.compareTo(a.interactionCount);
      });

    final categoryBreakdown = categoryAccumulators.values
        .map((entry) => entry.toDomain())
        .toList()
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

    final sessionAttendanceSeries = List<SessionAttendanceSnapshot>.from(
      sessionAttendance,
    )
      ..sort((a, b) => a.sessionDate.compareTo(b.sessionDate));

    final contactAttendanceSummary = contactAttendance.values
        .map((entry) => entry.toDomain())
        .toList()
      ..sort((a, b) {
        final aRate = a.attendanceRate ?? -1;
        final bRate = b.attendanceRate ?? -1;
        final comparison = bRate.compareTo(aRate);
        if (comparison != 0) {
          return comparison;
        }
        return b.presentCount.compareTo(a.presentCount);
      });

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

    final sessionsWithAttendance = sessionAttendanceSeries
        .where((snapshot) => snapshot.attendanceRate != null)
        .toList();
    final averageAttendanceRate = sessionsWithAttendance.isEmpty
        ? null
        : sessionsWithAttendance.fold<double>(
              0,
              (previousValue, element) =>
                  previousValue + (element.attendanceRate ?? 0),
            ) /
            sessionsWithAttendance.length;

    return AnalyticsSummary(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      totalInteractions: totalInteractions,
      totalMinutes: totalMinutes,
      contactInvestments: contactInvestments,
      categoryBreakdown: categoryBreakdown,
      timeline: timeline,
      contactGaps: contactGaps,
      sessionAttendance: sessionAttendanceSeries,
      contactAttendance: contactAttendanceSummary,
      averageAttendanceRate: averageAttendanceRate,
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

class _ContactAttendanceAccumulator {
  _ContactAttendanceAccumulator(this.contactId, this.contactName);

  final String contactId;
  final String contactName;
  int presentCount = 0;
  int totalCount = 0;

  ContactAttendanceSnapshot toDomain() {
    return ContactAttendanceSnapshot(
      contactId: contactId,
      contactName: contactName,
      presentCount: presentCount,
      totalCount: totalCount,
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
