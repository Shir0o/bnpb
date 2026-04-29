import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/prayer_request.dart';
import '../db/db_helper.dart';

enum RecommendationPriority {
  critical, // Overdue follow-up or extreme gap
  high, // Significant event or medium gap
  medium, // Standard follow-up
  low // General check-in
}

class FollowUpRecommendation {
  final Contact contact;
  final String reason;
  final RecommendationPriority priority;
  final DateTime? relativeDate;

  FollowUpRecommendation({
    required this.contact,
    required this.reason,
    required this.priority,
    this.relativeDate,
  });
}

class FollowUpRecommendationService {
  final DBHelper _dbHelper;

  FollowUpRecommendationService({DBHelper? dbHelper})
      : _dbHelper = dbHelper ?? DBHelper();

  Future<List<FollowUpRecommendation>> getRecommendations() async {
    final contacts = await _dbHelper.getContacts();
    final now = DateTime.now();
    final recommendations = <FollowUpRecommendation>[];

    for (final contact in contacts) {
      // Skip if there's a planned future follow-up
      if (_hasFutureFollowUp(contact, now)) continue;

      // 1. Check for answered prayer requests in the last 7 days (High priority)
      final recentAnsweredPrayer = _getRecentAnsweredPrayer(contact, now);
      if (recentAnsweredPrayer != null) {
        recommendations.add(FollowUpRecommendation(
          contact: contact,
          reason:
              'Celebrate answered prayer: "${recentAnsweredPrayer.description}"',
          priority: RecommendationPriority.high,
          relativeDate: recentAnsweredPrayer.answeredAt,
        ));
        continue; // One recommendation per contact is usually enough
      }

      // 2. Check for keywords in recent interactions (High priority)
      final followUpKeywordInteraction =
          _getInteractionWithFollowUpKeywords(contact);
      if (followUpKeywordInteraction != null) {
        recommendations.add(FollowUpRecommendation(
          contact: contact,
          reason:
              'Mentioned "follow up" in last meeting: "${followUpKeywordInteraction.summary}"',
          priority: RecommendationPriority.high,
          relativeDate: followUpKeywordInteraction.occurredAt,
        ));
        continue;
      }

      // 3. Check for pending prayer requests older than 14 days (Medium priority)
      final stalePrayerRequest = _getStalePrayerRequest(contact, now);
      if (stalePrayerRequest != null) {
        recommendations.add(FollowUpRecommendation(
          contact: contact,
          reason:
              'Check in on prayer request from ${stalenessInDays(stalePrayerRequest.requestedAt, now)} days ago',
          priority: RecommendationPriority.medium,
          relativeDate: stalePrayerRequest.requestedAt,
        ));
        continue;
      }

      // 4. Check for interaction gaps (Critical to Low)
      final latestInteraction = _getLatestInteraction(contact);
      if (latestInteraction == null) {
        // Never interacted - Low priority check-in
        recommendations.add(FollowUpRecommendation(
          contact: contact,
          reason: 'New contact: reach out for an initial meeting',
          priority: RecommendationPriority.low,
        ));
      } else {
        final gapDays = now.difference(latestInteraction.occurredAt).inDays;
        if (gapDays >= 60) {
          recommendations.add(FollowUpRecommendation(
            contact: contact,
            reason: 'Significant gap: no interaction in $gapDays days',
            priority: RecommendationPriority.critical,
            relativeDate: latestInteraction.occurredAt,
          ));
        } else if (gapDays >= 30) {
          recommendations.add(FollowUpRecommendation(
            contact: contact,
            reason: 'Monthly check-in: last seen $gapDays days ago',
            priority: RecommendationPriority.medium,
            relativeDate: latestInteraction.occurredAt,
          ));
        }
      }
    }

    // Sort by priority (critical first) and then by date
    recommendations.sort((a, b) {
      final priorityCompare = a.priority.index.compareTo(b.priority.index);
      if (priorityCompare != 0) return priorityCompare;

      if (a.relativeDate == null && b.relativeDate == null) return 0;
      if (a.relativeDate == null) return 1;
      if (b.relativeDate == null) return -1;
      return b.relativeDate!.compareTo(a.relativeDate!);
    });

    return recommendations;
  }

  bool _hasFutureFollowUp(Contact contact, DateTime now) {
    for (final interaction in contact.interactions) {
      if (interaction.followUpAt != null &&
          interaction.followUpAt!.isAfter(now)) {
        return true;
      }
    }
    return false;
  }

  PrayerRequest? _getRecentAnsweredPrayer(Contact contact, DateTime now) {
    for (final prayer in contact.prayerRequests) {
      if (prayer.status == PrayerRequestStatus.answered &&
          prayer.answeredAt != null) {
        final diff = now.difference(prayer.answeredAt!).inDays;
        if (diff >= 0 && diff <= 7) {
          return prayer;
        }
      }
    }
    return null;
  }

  Interaction? _getInteractionWithFollowUpKeywords(Contact contact) {
    if (contact.interactions.isEmpty) return null;

    // Check only the most recent interaction
    final latest = contact.interactions.first;
    final text = '${latest.summary} ${latest.notes ?? ''}'.toLowerCase();

    final keywords = [
      'follow up',
      'follow-up',
      'check in',
      'check-in',
      'next time',
      'remind me'
    ];
    for (final kw in keywords) {
      if (text.contains(kw)) {
        return latest;
      }
    }
    return null;
  }

  PrayerRequest? _getStalePrayerRequest(Contact contact, DateTime now) {
    for (final prayer in contact.prayerRequests) {
      if (prayer.status == PrayerRequestStatus.pending) {
        final diff = now.difference(prayer.requestedAt).inDays;
        if (diff >= 14) {
          return prayer;
        }
      }
    }
    return null;
  }

  Interaction? _getLatestInteraction(Contact contact) {
    if (contact.interactions.isEmpty) return null;
    return contact.interactions.first; // Assumes sorted by date desc
  }

  int stalenessInDays(DateTime date, DateTime now) {
    return now.difference(date).inDays;
  }
}
