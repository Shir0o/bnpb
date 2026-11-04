import 'package:bnpb/db/daos/prayer_request_dao.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/screens/prayer_diary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../repositories/mock_db_helper.dart';

class FakePrayerRequestDao extends PrayerRequestDao {
  FakePrayerRequestDao(this.db) : super(db);

  final PrayerFakeDB db;
  final statusCalls = <(int, PrayerRequestStatus, String?)>[];
  final prayed = <int, List<DateTime>>{};

  @override
  Future<Map<int, List<DateTime>>> getPrayedDates(List<int> ids) async => {
        for (final id in ids)
          if (prayed[id] != null) id: prayed[id]!
      };

  @override
  Future<bool> togglePrayedToday(int requestId, {DateTime? now}) async {
    final dates = prayed.putIfAbsent(requestId, () => []);
    if (dates.isNotEmpty) {
      dates.clear();
      return false;
    }
    dates.add(now ?? DateTime.now());
    return true;
  }

  @override
  Future<void> setStatus(
    int requestId,
    PrayerRequestStatus status, {
    String? comment,
    DateTime? now,
  }) async {
    statusCalls.add((requestId, status, comment));
    db.requests = [
      for (final r in db.requests)
        r.id == requestId
            ? r.copyWith(
                status: status,
                answeredAt: status == PrayerRequestStatus.answered
                    ? DateTime.now()
                    : null,
                clearAnsweredAt: status == PrayerRequestStatus.pending,
                reflectionNotes: comment,
              )
            : r,
    ];
  }
}

class PrayerFakeDB extends MockDBHelper {
  PrayerFakeDB(this.requests, this.contacts);

  List<PrayerRequest> requests;
  final List<Contact> contacts;
  late final FakePrayerRequestDao dao = FakePrayerRequestDao(this);

  @override
  PrayerRequestDao get prayerRequestDao => dao;

  @override
  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      List.of(requests);

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      contacts;
}

PrayerRequest _pendingRequest() => PrayerRequest(
      id: 1,
      participantIds: const ['c1'],
      description: 'Healing for Mum',
      status: PrayerRequestStatus.pending,
      requestedAt: DateTime(2026, 9, 1),
    );

Future<PrayerFakeDB> _pump(
  WidgetTester tester, {
  PrayerRequest? request,
}) async {
  final db = PrayerFakeDB(
    [request ?? _pendingRequest()],
    [Contact(id: 'c1', firstName: 'Ann', lastName: 'Lee')],
  );
  DBHelper.overrideForTest(db);
  addTearDown(DBHelper.resetTestOverride);

  await tester.pumpWidget(const MaterialApp(home: PrayerDiaryPage()));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US', null);
  });

  testWidgets('tabs show live counts and filter the list', (tester) async {
    await _pump(tester);

    expect(find.text('Ann Lee'), findsOneWidget);
    await tester.tap(find.text('Answered').first);
    await tester.pumpAndSettle();
    expect(find.text('Ann Lee'), findsNothing);
    expect(find.text('Nothing here yet.'), findsOneWidget);
  });

  testWidgets('Prayed toggles today without opening the detail page', (
    tester,
  ) async {
    final db = await _pump(tester);

    await tester.tap(find.text('Prayed'));
    await tester.pumpAndSettle();
    expect(find.text('Prayed today'), findsOneWidget);
    expect(find.text('Prayed 1× · today'), findsOneWidget);
    expect(db.dao.prayed[1], hasLength(1));
    expect(find.text('Prayer request details'), findsNothing);

    await tester.tap(find.text('Prayed today'));
    await tester.pumpAndSettle();
    expect(find.text('Not prayed for yet'), findsOneWidget);
  });

  testWidgets('marking a prayer Answered from the list persists the comment', (
    tester,
  ) async {
    final db = await _pump(tester);

    // The tab bar also reads "Answered"; the card action is the last match.
    await tester.tap(find.text('Answered').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'She is home');
    await tester.tap(find.text('Mark answered'));
    await tester.pumpAndSettle();

    expect(
        db.dao.statusCalls, [(1, PrayerRequestStatus.answered, 'She is home')]);
    expect(find.text('She is home'), findsOneWidget);
    expect(find.text('Reopen'), findsOneWidget);
  });

  testWidgets('reopening an answered prayer moves it back to pending', (
    tester,
  ) async {
    final db = await _pump(
      tester,
      request: _pendingRequest().copyWith(
        status: PrayerRequestStatus.answered,
        answeredAt: DateTime(2026, 9, 3),
      ),
    );

    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();

    expect(db.dao.statusCalls, [(1, PrayerRequestStatus.pending, null)]);
    expect(find.text('Prayed'), findsOneWidget);
  });
}
