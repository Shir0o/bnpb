import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/screens/prayer_diary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../repositories/mock_db_helper.dart';

class PrayerFakeDB extends MockDBHelper {
  PrayerFakeDB(this.requests, this.contacts);

  final List<PrayerRequest> requests;
  final List<Contact> contacts;
  final List<PrayerRequest> updates = [];

  @override
  Future<List<PrayerRequest>> getPrayerRequests({
    PrayerRequestStatus? status,
    int? limit,
    bool latestAnsweredFirst = false,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      requests;

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      contacts;

  @override
  Future<void> updatePrayerRequest(PrayerRequest request) async {
    updates.add(request);
  }
}

PrayerRequest _pendingRequest() => PrayerRequest(
      id: 1,
      participantIds: const ['c1'],
      description: 'Healing for Mum',
      status: PrayerRequestStatus.pending,
      requestedAt: DateTime(2026, 9, 1),
    );

Future<PrayerFakeDB> _pump(WidgetTester tester) async {
  final db = PrayerFakeDB(
    [_pendingRequest()],
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

  testWidgets(
    'the diary list exposes an explicit status control (not just a hidden tap)',
    (tester) async {
      await _pump(tester);

      expect(
        find.byType(PopupMenuButton<PrayerRequestStatus>),
        findsOneWidget,
        reason: 'each row needs a discoverable "change status" affordance',
      );
    },
  );

  testWidgets(
    'marking a prayer Archived straight from the list persists it and does '
    'not open the detail page',
    (tester) async {
      final db = await _pump(tester);

      await tester.tap(find.byType(PopupMenuButton<PrayerRequestStatus>));
      await tester.pumpAndSettle();

      // All three lifecycle states are offered explicitly.
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Answered'), findsWidgets);
      expect(find.text('Archived'), findsWidgets);

      await tester.tap(find.text('Archived').last);
      await tester.pumpAndSettle();

      expect(
        db.updates.map((r) => r.status),
        [PrayerRequestStatus.archived],
        reason: 'picking Archived must persist Archived directly',
      );
      expect(
        find.text('Prayer request details'),
        findsNothing,
        reason: 'acting on the list must not navigate into the detail page',
      );
    },
  );

  testWidgets(
    'marking a prayer Answered straight from the list persists it',
    (tester) async {
      final db = await _pump(tester);

      await tester.tap(find.byType(PopupMenuButton<PrayerRequestStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Answered').last);
      await tester.pumpAndSettle();

      final updated = db.updates.single;
      expect(updated.status, PrayerRequestStatus.answered);
      expect(updated.answeredAt, isNotNull);
    },
  );

  testWidgets(
    'moving an answered prayer back to Pending clears its answered date',
    (tester) async {
      final answered = PrayerRequest(
        id: 1,
        participantIds: const ['c1'],
        description: 'Healing for Mum',
        status: PrayerRequestStatus.answered,
        requestedAt: DateTime(2026, 9, 1),
        answeredAt: DateTime(2026, 9, 3),
      );
      final db = PrayerFakeDB(
        [answered],
        [Contact(id: 'c1', firstName: 'Ann', lastName: 'Lee')],
      );
      DBHelper.overrideForTest(db);
      addTearDown(DBHelper.resetTestOverride);

      await tester.pumpWidget(const MaterialApp(home: PrayerDiaryPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<PrayerRequestStatus>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PopupMenuItem<PrayerRequestStatus>, 'Pending'),
      );
      await tester.pumpAndSettle();

      final updated = db.updates.single;
      expect(updated.status, PrayerRequestStatus.pending);
      expect(
        updated.answeredAt,
        isNull,
        reason: 'a reopened prayer must not keep a stale answered date',
      );
    },
  );
}
