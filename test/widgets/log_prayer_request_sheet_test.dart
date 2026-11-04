import 'package:bnpb/db/daos/prayer_request_dao.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/screens/prayer_request_details_page.dart';
import 'package:bnpb/screens/select_prayer_people_page.dart';
import 'package:bnpb/services/reminder_coordinator.dart';
import 'package:bnpb/widgets/log_prayer_request_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repositories/mock_db_helper.dart';

class _FakeDao extends PrayerRequestDao {
  _FakeDao(super.dbHelper);

  final created = <(PrayerRequest, List<String>)>[];
  Map<int, List<DateTime>> prayed = {};

  @override
  Future<List<int>> createForEachContact(
    PrayerRequest template,
    List<String> contactIds,
  ) async {
    created.add((template, contactIds));
    return [for (var i = 0; i < contactIds.length; i++) 100 + i];
  }

  @override
  Future<Map<int, List<DateTime>>> getPrayedDates(List<int> ids) async =>
      prayed;
}

class _FakeDB extends MockDBHelper {
  _FakeDB({this.contacts = const [], this.requests = const []});

  final List<Contact> contacts;
  final List<PrayerRequest> requests;
  final updates = <PrayerRequest>[];
  final deleted = <int>[];
  late final _FakeDao dao = _FakeDao(this);

  @override
  PrayerRequestDao get prayerRequestDao => dao;

  @override
  Future<List<Contact>> getContacts({
    String? contactId,
    List<String>? contactIds,
    DateTime? updatedSince,
    bool includeDeleted = false,
  }) async =>
      contacts;

  @override
  Future<List<String>> getPrayerCategories() async => ['Health'];

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
  Future<void> updatePrayerRequest(PrayerRequest request) async {
    updates.add(request);
  }

  @override
  Future<void> deletePrayerRequest(int id) async => deleted.add(id);
}

class _FakeReminders extends ReminderCoordinator {
  _FakeReminders() : super.testHarness();

  @override
  Future<void> syncPrayerRequestReminder(
    Contact contact,
    PrayerRequest request, {
    bool silent = false,
  }) async {}

  @override
  Future<void> cancelPrayerRequestReminder(
    PrayerRequest request, {
    bool silent = false,
  }) async {}
}

final _ann = Contact(id: 'c1', firstName: 'Ann', lastName: 'Lee');
final _bob = Contact(id: 'c2', firstName: 'Bob', lastName: 'Ray');

PrayerRequest _request({
  PrayerRequestStatus status = PrayerRequestStatus.pending,
  List<String> participants = const ['c1'],
}) =>
    PrayerRequest(
      id: 7,
      participantIds: participants,
      description: 'Healing for Mum',
      status: status,
      requestedAt: DateTime(2026, 9, 1),
      reflectionNotes: 'Surgery on Friday',
    );

_FakeDB _install(_FakeDB db) {
  DBHelper.overrideForTest(db);
  ReminderCoordinator.overrideForTest(_FakeReminders());
  addTearDown(DBHelper.resetTestOverride);
  addTearDown(ReminderCoordinator.resetTestOverride);
  return db;
}

void main() {
  group('parsePrayerRequestText', () {
    test('strips tags from the description and keeps the last tag', () {
      final parsed = parsePrayerRequestText(
        '#family Recovery after knee  surgery #health',
      );
      expect(parsed.description, 'Recovery after knee surgery');
      expect(parsed.tag, 'health');
    });

    test('ignores # inside words and a bare #', () {
      final parsed = parsePrayerRequestText('Learning C# at work # soon');
      expect(parsed.description, 'Learning C# at work # soon');
      expect(parsed.tag, isNull);
    });

    test('supports non-Latin tags and keeps line breaks', () {
      final parsed = parsePrayerRequestText('第一行 #健康\nsecond line');
      expect(parsed.description, '第一行\nsecond line');
      expect(parsed.tag, '健康');
    });
  });

  group('categoryFromTag', () {
    test('reuses an existing category regardless of case', () {
      expect(categoryFromTag('health', ['Health', 'Work']), 'Health');
    });

    test('capitalises a new category and reads _ as a space', () {
      expect(categoryFromTag('small_group', const []), 'Small group');
    });
  });

  testWidgets('saving for two people creates one request per person', (
    tester,
  ) async {
    final db = _install(
      _FakeDB(
        requests: [
          _request(),
          _request(participants: ['c2']),
        ],
      ),
    );
    final saved = <PrayerRequest>[];
    String? popResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popResult = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => LogPrayerRequestSheet(
                  availableContacts: [_ann, _bob],
                  onSaved: saved.add,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Both are suggested because they have open requests.
    await tester.tap(find.text('Ann Lee'));
    await tester.pump();
    await tester.tap(find.text('Bob Ray'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).first,
      'Recovery after surgery #health',
    );
    await tester.pump();

    expect(
      find.text('Saves as 2 separate requests, one per person.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save 2'));
    await tester.pumpAndSettle();

    final (template, contactIds) = db.dao.created.single;
    expect(contactIds, ['c1', 'c2']);
    expect(template.description, 'Recovery after surgery');
    expect(template.category, 'Health');
    expect(template.status, PrayerRequestStatus.pending);
    expect(saved.map((r) => r.participantIds), [
      ['c1'],
      ['c2'],
    ]);
    expect(saved.map((r) => r.id), [100, 101]);
    expect(popResult, 'created');
  });

  testWidgets('editing through the sheet updates the one request', (
    tester,
  ) async {
    final db = _install(_FakeDB());
    final original = _request();
    String? popResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popResult = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => LogPrayerRequestSheet(
                  initialRequest: original,
                  availableContacts: [_ann],
                  onSaved: (_) {},
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Healing for Dad');
    await tester.tap(find.byTooltip('Save request'));
    await tester.pumpAndSettle();

    final updated = db.updates.single;
    expect(updated.id, 7);
    expect(updated.syncId, original.syncId);
    expect(updated.description, 'Healing for Dad');
    expect(updated.participantIds, ['c1']);
    expect(updated.reflectionNotes, 'Surgery on Friday');
    expect(db.dao.created, isEmpty);
    expect(popResult, 'updated');
  });

  group('PrayerRequestDetailsPage', () {
    /// Pushes the page and returns a getter for its pop result.
    Future<bool? Function()> pumpDetails(
      WidgetTester tester,
      PrayerRequest request,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PrayerRequestDetailsPage(
                      request: request,
                      initialContacts: [_ann],
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('choosing Answered saves it with today as answered date', (
      tester,
    ) async {
      final db = _install(_FakeDB(contacts: [_ann]));
      db.dao.prayed = {
        7: [DateTime(2026, 9, 2, 8)],
      };
      await pumpDetails(tester, _request());

      expect(find.text('Prayed'), findsOneWidget);
      await tester.tap(find.text('Answered'));
      await tester.pumpAndSettle();

      final updated = db.updates.single;
      expect(updated.status, PrayerRequestStatus.answered);
      expect(updated.answeredAt, isNotNull);
      expect(updated.reflectionNotes, 'Surgery on Friday');
      expect(find.text('How was it answered?'), findsOneWidget);
      expect(find.text('Marked answered'), findsOneWidget);
    });

    testWidgets('text edits save on leaving and the page reports an update', (
      tester,
    ) async {
      final db = _install(_FakeDB(contacts: [_ann]));
      final result = await pumpDetails(tester, _request());

      await tester.enterText(find.byType(TextField).first, 'Healing for Dad');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(db.updates.single.description, 'Healing for Dad');
      expect(result(), isTrue);
    });

    testWidgets('delete asks first, then deletes and pops true', (
      tester,
    ) async {
      final db = _install(_FakeDB(contacts: [_ann]));
      final result = await pumpDetails(tester, _request());

      await tester.scrollUntilVisible(
        find.text('Delete request'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete request'));
      await tester.pumpAndSettle();
      expect(db.deleted, isEmpty);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(db.deleted, [7]);
      expect(result(), isTrue);
    });
  });

  testWidgets('people picker explains separate requests and returns picks', (
    tester,
  ) async {
    _install(
      _FakeDB(
        contacts: [_bob, _ann],
        requests: [_request()],
      ),
    );
    List<Contact>? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await SelectPrayerPeoplePage.open(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('1 open'), findsOneWidget);
    expect(find.text('No requests'), findsOneWidget);
    await tester.tap(find.text('Bob Ray'));
    await tester.tap(find.text('Ann Lee'));
    await tester.pump();
    expect(find.textContaining('2 separate requests'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ann');
    await tester.pump();
    expect(find.text('No requests'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked?.map((c) => c.id), ['c2', 'c1']);
  });
}
