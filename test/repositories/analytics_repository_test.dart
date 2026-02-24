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
  });
}
