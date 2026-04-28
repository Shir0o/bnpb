import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';

import 'package:bnpb/repositories/analytics_repository.dart';
import 'mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  List<Contact> contacts = [];
  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async {
    if (contactId != null) {
      return contacts.where((c) => c.id == contactId).toList();
    }
    if (contactIds != null) {
      return contacts.where((c) => contactIds.contains(c.id)).toList();
    }
    return contacts;
  }
}

void main() {
  group('AnalyticsRepository', () {
    late AnalyticsRepository repository;
    late _TestDBHelper dbHelper;

    setUp(() {
      dbHelper = _TestDBHelper();
      repository = AnalyticsRepository(dbHelper: dbHelper);
    });

    test('buildSummary aggregates interactions correctly', () async {
      final now = DateTime.now();
      final c1 = Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 1)),
            summary: 'Chat',
            medium: 'phone',
            durationMinutes: 30,
            notes: 'Work',
          ),
          Interaction(
            occurredAt: now.subtract(const Duration(days: 2)),
            summary: 'Coffee',
            medium: 'in_person',
            durationMinutes: 60,
            notes: 'Social',
          ),
        ],
      );
      dbHelper.contacts.add(c1);

      final summary = await repository.buildSummary();

      expect(summary.totalMinutes, 90);
      expect(summary.totalInteractions, 2);

      // Category breakdown (should be empty because interactions don't have categories anymore)
      expect(summary.categoryBreakdown.length, 0);
    });

    test('buildSummary respects date range', () async {
      final now = DateTime.now();
      final c1 = Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 10)), // Outside
            summary: 'Old',
            medium: 'phone',
            durationMinutes: 60,
          ),
          Interaction(
            occurredAt: now.subtract(const Duration(days: 1)), // Inside
            summary: 'New',
            medium: 'phone',
            durationMinutes: 30,
          ),
        ],
      );
      dbHelper.contacts.add(c1);

      final summary = await repository.buildSummary(
        rangeStart: now.subtract(const Duration(days: 5)),
      );

      expect(summary.totalMinutes, 30);
      expect(summary.totalInteractions, 1);
    });

    test('buildSummary identifies contacts with follow-ups', () async {
      final now = DateTime.now();

      // Contact with no follow-up
      final c1 = Contact(
        id: 'c1',
        firstName: 'Alice',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 1)),
            summary: 'Chat',
            medium: 'phone',
          ),
        ],
      );

      // Contact with future follow-up
      final c2 = Contact(
        id: 'c2',
        firstName: 'Bob',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 1)),
            summary: 'Coffee',
            medium: 'in_person',
            followUpAt: now.add(const Duration(days: 1)),
          ),
        ],
      );

      // Contact with overdue follow-up (unaddressed)
      final c3 = Contact(
        id: 'c3',
        firstName: 'Charlie',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 10)),
            summary: 'Old chat',
            medium: 'phone',
            followUpAt: now.subtract(const Duration(days: 5)),
          ),
        ],
      );

      // Contact with overdue follow-up but addressed
      final c4 = Contact(
        id: 'c4',
        firstName: 'David',
        interactions: [
          Interaction(
            occurredAt: now.subtract(const Duration(days: 10)),
            summary: 'Old chat',
            medium: 'phone',
            followUpAt: now.subtract(const Duration(days: 5)),
          ),
          Interaction(
            occurredAt:
                now.subtract(const Duration(days: 4)), // After followUpAt
            summary: 'Follow-up chat',
            medium: 'phone',
          ),
        ],
      );

      dbHelper.contacts.addAll([c1, c2, c3, c4]);

      final summary = await repository.buildSummary();
      final gaps = summary.contactGaps;

      final g1 = gaps.firstWhere((g) => g.contactId == 'c1');
      final g2 = gaps.firstWhere((g) => g.contactId == 'c2');
      final g3 = gaps.firstWhere((g) => g.contactId == 'c3');
      final g4 = gaps.firstWhere((g) => g.contactId == 'c4');

      expect(g1.hasFollowUp, isFalse);
      expect(g2.hasFollowUp, isTrue);
      expect(g3.hasFollowUp, isTrue);
      expect(g4.hasFollowUp, isFalse);
    });
  });
}
