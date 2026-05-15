import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/repositories/relationship_insights_repository.dart';

import 'mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  final List<Contact> contacts = [];
  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    return contacts;
  }
}

void main() {
  group('RelationshipInsightsRepository', () {
    late _TestDBHelper db;
    late DateTime now;
    late RelationshipInsightsRepository repo;

    setUp(() {
      db = _TestDBHelper();
      now = DateTime(2026, 5, 15, 12);
      repo = RelationshipInsightsRepository(dbHelper: db, now: () => now);
    });

    Interaction interaction(DateTime when, {DateTime? followUpAt}) =>
        Interaction(
          occurredAt: when,
          summary: 's',
          medium: 'phone',
          durationMinutes: 10,
          followUpAt: followUpAt,
        );

    test('flags a drifting contact when the current gap dwarfs the median',
        () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          interaction(now.subtract(const Duration(days: 120))),
          interaction(now.subtract(const Duration(days: 113))),
          interaction(now.subtract(const Duration(days: 106))),
          interaction(now.subtract(const Duration(days: 99))),
          interaction(now.subtract(const Duration(days: 60))),
        ],
      ));

      final insights = await repo.buildInsights();
      final drift = insights.firstWhere(
        (i) => i.type == RelationshipInsightType.driftingContact,
      );
      expect(drift.contactId, 'c1');
      expect(drift.details!['medianGapDays'], 7);
      expect(drift.details!['currentGapDays'], 60);
    });

    test('does not flag drift when current gap matches typical cadence',
        () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          interaction(now.subtract(const Duration(days: 28))),
          interaction(now.subtract(const Duration(days: 21))),
          interaction(now.subtract(const Duration(days: 14))),
          interaction(now.subtract(const Duration(days: 7))),
        ],
      ));

      final insights = await repo.buildInsights();
      expect(
        insights
            .where((i) => i.type == RelationshipInsightType.driftingContact),
        isEmpty,
      );
    });

    test('requires the minimum interaction count for drift', () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          interaction(now.subtract(const Duration(days: 90))),
          interaction(now.subtract(const Duration(days: 80))),
        ],
      ));

      final insights = await repo.buildInsights();
      expect(
        insights
            .where((i) => i.type == RelationshipInsightType.driftingContact),
        isEmpty,
      );
    });

    test('flags a silence streak past the 60-day threshold', () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Bob',
        interactions: [
          interaction(now.subtract(const Duration(days: 75))),
        ],
      ));

      final insights = await repo.buildInsights();
      final silence = insights.firstWhere(
        (i) => i.type == RelationshipInsightType.silenceStreak,
      );
      expect(silence.contactId, 'c1');
      expect(silence.details!['gapDays'], 75);
    });

    test('skips silence streak when the contact was contacted recently',
        () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Bob',
        interactions: [
          interaction(now.subtract(const Duration(days: 10))),
        ],
      ));

      final insights = await repo.buildInsights();
      expect(
        insights.where((i) => i.type == RelationshipInsightType.silenceStreak),
        isEmpty,
      );
    });

    test('flags stale prayer requests when 3+ pending are older than 30 days',
        () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Carol',
        prayerRequests: [
          PrayerRequest(
            participantIds: const ['c1'],
            description: 'r1',
            status: PrayerRequestStatus.pending,
            requestedAt: now.subtract(const Duration(days: 90)),
          ),
          PrayerRequest(
            participantIds: const ['c1'],
            description: 'r2',
            status: PrayerRequestStatus.pending,
            requestedAt: now.subtract(const Duration(days: 60)),
          ),
          PrayerRequest(
            participantIds: const ['c1'],
            description: 'r3',
            status: PrayerRequestStatus.pending,
            requestedAt: now.subtract(const Duration(days: 35)),
          ),
          PrayerRequest(
            participantIds: const ['c1'],
            description: 'recent',
            status: PrayerRequestStatus.pending,
            requestedAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      ));

      final insights = await repo.buildInsights();
      final stale = insights.firstWhere(
        (i) => i.type == RelationshipInsightType.stalePrayerRequests,
      );
      expect(stale.details!['pendingCount'], 3);
      expect(stale.details!['oldestDays'], 90);
    });

    test('celebrates a prayer answered within the last week', () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Dana',
        prayerRequests: [
          PrayerRequest(
            participantIds: const ['c1'],
            description: 'job',
            status: PrayerRequestStatus.answered,
            requestedAt: now.subtract(const Duration(days: 30)),
            answeredAt: now.subtract(const Duration(days: 2)),
          ),
          PrayerRequest(
            participantIds: const ['c1'],
            description: 'old',
            status: PrayerRequestStatus.answered,
            requestedAt: now.subtract(const Duration(days: 90)),
            answeredAt: now.subtract(const Duration(days: 30)),
          ),
        ],
      ));

      final insights = await repo.buildInsights();
      final answered = insights
          .where((i) => i.type == RelationshipInsightType.answeredPrayer)
          .toList();
      expect(answered, hasLength(1));
      expect(answered.single.details!['description'], 'job');
    });

    test('computes the follow-up completion rate when sample is large enough',
        () async {
      // Five past follow-ups, three completed (had an interaction after the
      // follow-up date).
      final contact = Contact(
        id: 'c1',
        firstName: 'Eve',
        interactions: [
          interaction(now.subtract(const Duration(days: 100)),
              followUpAt: now.subtract(const Duration(days: 90))),
          interaction(now.subtract(const Duration(days: 85))), // completes #1
          interaction(now.subtract(const Duration(days: 80)),
              followUpAt: now.subtract(const Duration(days: 70))),
          interaction(now.subtract(const Duration(days: 60))), // completes #2
          interaction(now.subtract(const Duration(days: 55)),
              followUpAt: now.subtract(const Duration(days: 50))),
          interaction(now.subtract(const Duration(days: 40))), // completes #3
          // Trailing pair of unmet follow-ups (no later interactions exist).
          interaction(now.subtract(const Duration(days: 20)),
              followUpAt: now.subtract(const Duration(days: 10))),
          interaction(now.subtract(const Duration(days: 15)),
              followUpAt: now.subtract(const Duration(days: 5))),
        ],
      );
      db.contacts.add(contact);

      final insights = await repo.buildInsights();
      final rate = insights.firstWhere(
        (i) => i.type == RelationshipInsightType.followUpCompletionRate,
      );
      expect(rate.details!['totalDue'], 5);
      expect(rate.details!['completed'], 3);
      expect(rate.details!['percent'], 60);
    });

    test('skips follow-up rate when sample is too small', () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Eve',
        interactions: [
          interaction(now.subtract(const Duration(days: 100)),
              followUpAt: now.subtract(const Duration(days: 90))),
          interaction(now.subtract(const Duration(days: 85))),
        ],
      ));
      final insights = await repo.buildInsights();
      expect(
        insights.where(
            (i) => i.type == RelationshipInsightType.followUpCompletionRate),
        isEmpty,
      );
    });

    test('insight ids are stable across rebuilds', () async {
      db.contacts.add(Contact(
        id: 'c1',
        firstName: 'Bob',
        interactions: [
          interaction(now.subtract(const Duration(days: 75))),
        ],
      ));
      final a = await repo.buildInsights();
      final b = await repo.buildInsights();
      expect(
        a.map((i) => i.id).toList(),
        b.map((i) => i.id).toList(),
      );
      expect(a.single.id, 'silence:c1');
    });
  });
}
