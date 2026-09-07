import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/prayer_request.dart';
import '../db/db_helper.dart';

enum RecommendationPriority {
  critical, // Overdue follow-up or extreme gap
  high, // Significant event or medium gap
  medium, // Standard follow-up
  low, // General check-in
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

  static final RegExp _keywordRegExp = RegExp(
    r'follow[- ]up|check[- ]in|next time|remind me',
    caseSensitive: false,
  );

  FollowUpRecommendationService({DBHelper? dbHelper})
      : _dbHelper = dbHelper ?? DBHelper();

  Future<List<FollowUpRecommendation>> getRecommendations({
    bool forceRefresh = false,
  }) async {
    final contacts = await _dbHelper.getContacts();
    final now = DateTime.now();
    final recommendations = <FollowUpRecommendation>[];

    for (int c = 0; c < contacts.length; c++) {
      final contact = contacts[c];
      final interactions = contact.interactions;

      // Skip if there's a planned future follow-up
      if (_hasFutureFollowUp(interactions, now)) continue;

      // 1. Check for answered prayer requests in the last 7 days (High priority)
      final recentAnsweredPrayer =
          _getRecentAnsweredPrayer(contact.prayerRequests, now);
      if (recentAnsweredPrayer != null) {
        recommendations.add(
          FollowUpRecommendation(
            contact: contact,
            reason:
                'Celebrate answered prayer: "${recentAnsweredPrayer.description}"',
            priority: RecommendationPriority.high,
            relativeDate: recentAnsweredPrayer.answeredAt,
          ),
        );
        continue; // One recommendation per contact is usually enough
      }

      // 2. Check for keywords in recent interactions (High priority)
      final followUpKeywordInteraction = _getInteractionWithFollowUpKeywords(
        interactions,
      );
      if (followUpKeywordInteraction != null) {
        recommendations.add(
          FollowUpRecommendation(
            contact: contact,
            reason:
                'Mentioned "follow up" in last meeting: "${followUpKeywordInteraction.summary}"',
            priority: RecommendationPriority.high,
            relativeDate: followUpKeywordInteraction.occurredAt,
          ),
        );
        continue;
      }

      // 3. Check for pending prayer requests older than 14 days (Medium priority)
      final stalePrayerRequest =
          _getStalePrayerRequest(contact.prayerRequests, now);
      if (stalePrayerRequest != null) {
        recommendations.add(
          FollowUpRecommendation(
            contact: contact,
            reason:
                'Check in on prayer request from ${stalenessInDays(stalePrayerRequest.requestedAt, now)} days ago',
            priority: RecommendationPriority.medium,
            relativeDate: stalePrayerRequest.requestedAt,
          ),
        );
        continue;
      }

      // 4. Check for interaction gaps (Critical to Low)
      if (interactions.isEmpty) {
        // Never interacted - Low priority check-in
        recommendations.add(
          FollowUpRecommendation(
            contact: contact,
            reason: 'New contact: reach out for an initial meeting',
            priority: RecommendationPriority.low,
          ),
        );
      } else {
        final latestInteraction = interactions.first;
        final gapDays = now.difference(latestInteraction.occurredAt).inDays;
        if (gapDays >= 60) {
          recommendations.add(
            FollowUpRecommendation(
              contact: contact,
              reason: 'Significant gap: no interaction in $gapDays days',
              priority: RecommendationPriority.critical,
              relativeDate: latestInteraction.occurredAt,
            ),
          );
        } else if (gapDays >= 30) {
          recommendations.add(
            FollowUpRecommendation(
              contact: contact,
              reason: 'Monthly check-in: last seen $gapDays days ago',
              priority: RecommendationPriority.medium,
              relativeDate: latestInteraction.occurredAt,
            ),
          );
        }
      }
    }

    // Sort by priority (critical first) and then by date
    if (recommendations.length > 1) {
      recommendations.sort((a, b) {
        final priorityCompare = a.priority.index.compareTo(b.priority.index);
        if (priorityCompare != 0) return priorityCompare;

        if (a.relativeDate == null && b.relativeDate == null) return 0;
        if (a.relativeDate == null) return 1;
        if (b.relativeDate == null) return -1;
        return b.relativeDate!.compareTo(a.relativeDate!);
      });
    }

    return recommendations;
  }

  bool _hasFutureFollowUp(List<Interaction> interactions, DateTime now) {
    for (int i = 0; i < interactions.length; i++) {
      final followUpAt = interactions[i].followUpAt;
      if (followUpAt != null && followUpAt.isAfter(now)) {
        return true;
      }
    }
    return false;
  }

  PrayerRequest? _getRecentAnsweredPrayer(
      List<PrayerRequest> prayerRequests, DateTime now) {
    for (int i = 0; i < prayerRequests.length; i++) {
      final prayer = prayerRequests[i];
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

  Interaction? _getInteractionWithFollowUpKeywords(
      List<Interaction> interactions) {
    if (interactions.isEmpty) return null;

    final latest = interactions.first;
    if (_keywordRegExp.hasMatch(latest.summary)) {
      return latest;
    }
    final notes = latest.notes;
    if (notes != null && _keywordRegExp.hasMatch(notes)) {
      return latest;
    }
    return null;
  }

  PrayerRequest? _getStalePrayerRequest(
      List<PrayerRequest> prayerRequests, DateTime now) {
    for (int i = 0; i < prayerRequests.length; i++) {
      final prayer = prayerRequests[i];
      if (prayer.status == PrayerRequestStatus.pending) {
        final diff = now.difference(prayer.requestedAt).inDays;
        if (diff >= 14) {
          return prayer;
        }
      }
    }
    return null;
  }

  int stalenessInDays(DateTime date, DateTime now) {
    return now.difference(date).inDays;
  }
}
