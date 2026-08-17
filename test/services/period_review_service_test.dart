import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/stage_move.dart';

import 'package:bnpb/services/period_review_service.dart';
import '../repositories/mock_db_helper.dart';

class _TestDBHelper extends MockDBHelper {
  List<Contact> contacts = [];
  final List<StageMove> stageMoves = [];

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

  @override
  Future<Contact?> getContactById(String id) async {
    for (final contact in contacts) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  @override
  Future<void> setContactStage({
    required String contactId,
    required String toStage,
    String? fromStage,
    DateTime? movedAt,
  }) async {
    final index = contacts.indexWhere((c) => c.id == contactId);
    if (index >= 0) {
      contacts[index] = contacts[index].copyWith(stage: toStage);
    }
    stageMoves.add(
      StageMove(
        contactId: contactId,
        fromStage: fromStage,
        toStage: toStage,
        movedAt: movedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<List<StageMove>> getStageMoves(
      {DateTime? start, DateTime? end}) async {
    return stageMoves
        .where(
          (m) =>
              (start == null || !m.movedAt.isBefore(start)) &&
              (end == null || m.movedAt.isBefore(end)),
        )
        .toList();
  }
}

void main() {
  final now = DateTime(2026, 8, 17, 10, 30);

  late _TestDBHelper dbHelper;
  late PeriodReviewService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dbHelper = _TestDBHelper();
    service = PeriodReviewService(dbHelper: dbHelper, now: () => now);
    DBHelper.overrideForTest(dbHelper);
  });

  tearDown(() {
    DBHelper.resetTestOverride();
  });

  Contact contact(
    String id,
    String name, {
    List<Interaction> interactions = const [],
    List<PrayerRequest> prayers = const [],
    String? stage,
  }) {
    final parts = name.split(' ');
    return Contact(
      id: id,
      firstName: parts.first,
      lastName: parts.length > 1 ? parts.last : null,
      interactions: interactions,
      prayerRequests: prayers,
      stage: stage,
      updatedAt: now,
    );
  }

  Interaction interaction(DateTime at, {int minutes = 30}) {
    return Interaction(
      occurredAt: at,
      summary: 'Chat',
      medium: 'Call',
      durationMinutes: minutes,
    );
  }

  void move(
    String contactId,
    String from,
    String to,
    DateTime at,
  ) {
    dbHelper.stageMoves.add(
      StageMove(
        contactId: contactId,
        fromStage: from,
        toStage: to,
        movedAt: at,
      ),
    );
  }

  test('empty data reports no alert', () async {
    final data = await service.build(period: ReviewPeriod.month);

    expect(data.hasContacts, isFalse);
    expect(data.showAlert, isFalse);
    expect(data.periodLabel, 'August 2026');
    expect(data.period.chip, 'Month');
  });

  test('attention alert fires when nobody reached regular contact', () async {
    dbHelper.contacts.add(
      contact('c1', 'Bob Jones', interactions: [
        interaction(DateTime(2026, 8, 15)),
      ]),
    );

    final data = await service.build(period: ReviewPeriod.month);

    expect(data.hasContacts, isTrue);
    expect(data.attentionCount, 1);
    expect(data.showAlert, isTrue);
    expect(data.alertTitle, 'August 2026 is not adding up');
    expect(data.alertSub, '1 thing needing attention · open the review');

    // No confirmed moves → no movement, faithful-but-stuck verdict.
    expect(data.verdictKind, ReviewMarkKind.attention);
    expect(data.verdict, contains('no one moved forward'));
    expect(data.moveSummary, '0 forward · 0 back');
    expect(data.hasMoves, isFalse);
  });

  test('confirmed move into regular contact clears the alert', () async {
    dbHelper.contacts.add(
      contact(
        'c1',
        'Alice Smith',
        interactions: [
          interaction(DateTime(2026, 6, 10)),
          interaction(DateTime(2026, 6, 20)),
          interaction(DateTime(2026, 8, 15)),
        ],
        stage: 'Regular contact',
      ),
    );
    move('c1', 'Second contact', 'Regular contact', DateTime(2026, 8, 10));

    final data = await service.build(period: ReviewPeriod.month);

    expect(data.attentionCount, 0);
    expect(data.showAlert, isFalse);
    expect(data.verdictKind, ReviewMarkKind.bright);
    expect(data.verdict, contains('Alice Smith became a regular contact'));
    expect(data.intentionGot, 1);
    expect(data.intentionGoal, 1);
    expect(data.intentionKind, ReviewMarkKind.bright);
    expect(data.hasMoves, isTrue);
    expect(data.transitions.single.path, 'Second contact → Regular contact');
    expect(
      data.marks.any((m) => m.title.contains('became a regular contact')),
      isTrue,
    );
  });

  test('forward and backward moves are summarized and tagged', () async {
    dbHelper.contacts.addAll([
      contact(
        'c1',
        'Alice',
        stage: 'Regular contact',
      ),
      contact('c2', 'Bob', stage: 'Second contact'),
    ]);
    move('c1', 'Second contact', 'Regular contact', DateTime(2026, 8, 3));
    move('c2', 'Regular contact', 'Second contact', DateTime(2026, 8, 9));

    final data = await service.build(period: ReviewPeriod.month);

    expect(data.moveSummary, '1 forward · 1 back');
    final forward = data.transitions.where((t) => t.forward).toList();
    final backward = data.transitions.where((t) => !t.forward).toList();
    expect(forward.single.path, 'Second contact → Regular contact');
    expect(backward.single.path, 'Regular contact → Second contact');
  });

  test('funnel distributes contacts by resolved stage', () async {
    dbHelper.contacts.addAll([
      contact('c1', 'Abe', interactions: const []),
      contact('c2', 'Bea', interactions: const [], stage: 'First contact'),
      contact('c3', 'Cal', stage: 'Second contact'),
      contact('c4', 'Dan', stage: 'Regular contact'),
      contact('c5', 'Eve', stage: 'Group meeting'),
      contact('c6', 'Fay', stage: 'Laboring'),
    ]);

    final data = await service.build(period: ReviewPeriod.year);

    expect(
      data.funnel.map((e) => (e.name, e.count)).toList(),
      [
        ('First contact', 2),
        ('Second contact', 1),
        ('Regular contact', 1),
        ('Group meeting', 1),
        ('Church meeting', 0),
        ('Laboring', 1),
      ],
    );
    // Regular contact bar is marked as the line.
    expect(data.funnel[2].note, 'the line');
  });

  test('effort rows report deltas against the previous period', () async {
    dbHelper.contacts.add(
      contact('c1', 'Cara', interactions: [
        interaction(DateTime(2026, 7, 5)),
        interaction(DateTime(2026, 8, 2)),
        interaction(DateTime(2026, 8, 9)),
      ]),
    );

    final data = await service.build(period: ReviewPeriod.month);

    final ic = data.effort.firstWhere((e) => e.label == 'Interactions logged');
    expect(ic.value, 2);
    expect(ic.delta, 1);

    final mins = data.effort.firstWhere((e) => e.label == 'Minutes invested');
    expect(mins.value, 60);
    expect(mins.delta, 30);
  });

  test('prayer answers in period count toward effort', () async {
    dbHelper.contacts.add(
      contact('c1', 'Dan', prayers: [
        PrayerRequest(
          id: 1,
          participantIds: ['c1'],
          description: 'Job',
          status: PrayerRequestStatus.answered,
          requestedAt: DateTime(2026, 6, 1),
          answeredAt: DateTime(2026, 8, 3),
        ),
      ]),
    );

    final data = await service.build(period: ReviewPeriod.month);

    final ans = data.effort.firstWhere((e) => e.label == 'Prayers answered');
    expect(ans.value, 1);
  });

  test('open prayer requests older than 60 days surface in care', () async {
    dbHelper.contacts.add(
      contact('c1', 'Eve', prayers: [
        PrayerRequest(
          id: 1,
          participantIds: ['c1'],
          description: 'Health',
          status: PrayerRequestStatus.pending,
          requestedAt: DateTime(2026, 4, 1),
        ),
      ]),
    );

    final data = await service.build(period: ReviewPeriod.month);

    final old = data.care.firstWhere((c) => c.label == 'prayers open 60+ days');
    expect(old.value, '1');
    expect(old.bad, isTrue);
  });

  test('activity beyond a confirmed stage produces a suggestion', () async {
    dbHelper.contacts.add(
      contact(
        'c1',
        'Gus',
        interactions: [
          for (var i = 1; i <= 5; i++) interaction(DateTime(2026, 8, i)),
        ],
        stage: 'First contact',
      ),
    );

    final data = await service.build(period: ReviewPeriod.month);

    expect(data.hasSuggestions, isTrue);
    expect(data.suggestions.single.name, 'Gus');
    expect(data.suggestions.single.from, 'First contact');
    expect(data.suggestions.single.to, 'Second contact');
    expect(data.suggestions.single.why, contains('interactions'));
  });
}
