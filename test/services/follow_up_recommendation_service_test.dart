import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/follow_up_recommendation_service.dart';
import 'package:bnpb/db/db_helper.dart';

class MockDBHelper extends Mock implements DBHelper {}

void main() {
  late MockDBHelper mockDbHelper;
  late FollowUpRecommendationService service;

  setUp(() {
    mockDbHelper = MockDBHelper();
    service = FollowUpRecommendationService(dbHelper: mockDbHelper);
  });

  test('getRecommendations returns correct recommendations and priority ordering', () async {
    final now = DateTime.now();

    final c1 = Contact(
      id: '1',
      firstName: 'Future Follow Up Contact',
      updatedAt: now,
      interactions: [
        Interaction(
          id: 1,
          occurredAt: now.subtract(const Duration(days: 1)),
          summary: 'Met up',
          medium: 'inPerson',
          followUpAt: now.add(const Duration(days: 2)),
          updatedAt: now,
        ),
      ],
    );

    final c2 = Contact(
      id: '2',
      firstName: 'Recent Answered Prayer Contact',
      updatedAt: now,
      prayerRequests: [
        PrayerRequest(
          id: 1,
          participantIds: ['2'],
          description: 'Healed',
          status: PrayerRequestStatus.answered,
          answeredAt: now.subtract(const Duration(days: 2)),
          requestedAt: now.subtract(const Duration(days: 20)),
          updatedAt: now,
        ),
      ],
    );

    final c3 = Contact(
      id: '3',
      firstName: 'Keyword Interaction Contact',
      updatedAt: now,
      interactions: [
        Interaction(
          id: 2,
          occurredAt: now.subtract(const Duration(days: 5)),
          summary: 'Please follow up next week',
          medium: 'inPerson',
          updatedAt: now,
        ),
      ],
    );

    final c4 = Contact(
      id: '4',
      firstName: 'Stale Prayer Request Contact',
      updatedAt: now,
      prayerRequests: [
        PrayerRequest(
          id: 2,
          participantIds: ['4'],
          description: 'Job search',
          status: PrayerRequestStatus.pending,
          requestedAt: now.subtract(const Duration(days: 15)),
          updatedAt: now,
        ),
      ],
    );

    final c5 = Contact(
      id: '5',
      firstName: 'No Interactions Contact',
      updatedAt: now,
    );

    final c6 = Contact(
      id: '6',
      firstName: 'Critical Gap Contact',
      updatedAt: now,
      interactions: [
        Interaction(
          id: 3,
          occurredAt: now.subtract(const Duration(days: 70)),
          summary: 'Old chat',
          medium: 'inPerson',
          updatedAt: now,
        ),
      ],
    );

    final c7 = Contact(
      id: '7',
      firstName: 'Medium Gap Contact',
      updatedAt: now,
      interactions: [
        Interaction(
          id: 4,
          occurredAt: now.subtract(const Duration(days: 35)),
          summary: 'Last month chat',
          medium: 'inPerson',
          updatedAt: now,
        ),
      ],
    );

    when(() => mockDbHelper.getContacts()).thenAnswer((_) async => [c1, c2, c3, c4, c5, c6, c7]);

    final recommendations = await service.getRecommendations();

    expect(recommendations.map((r) => r.contact.id).toList(), [
      '6', // Critical gap (priority: critical)
      '2', // Answered prayer (priority: high)
      '3', // Keyword (priority: high)
      '4', // Stale prayer (priority: medium)
      '7', // Medium gap (priority: medium)
      '5', // New contact (priority: low)
    ]);
  });
}
