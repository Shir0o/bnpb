import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/stage_move.dart';
import 'package:bnpb/screens/review_page.dart';
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

Contact _contact(
  String id,
  String name,
  int interactionCount, {
  int monthsAgo = 0,
  String? stage,
}) {
  final parts = name.split(' ');
  final now = DateTime.now();
  return Contact(
    id: id,
    firstName: parts.first,
    lastName: parts.length > 1 ? parts.last : null,
    updatedAt: now,
    stage: stage,
    interactions: [
      for (var i = 0; i < interactionCount; i++)
        Interaction(
          occurredAt: monthsAgo == 0
              ? DateTime(now.year, now.month, 2 + i)
              : DateTime(now.year, now.month - monthsAgo, 1)
                  .subtract(Duration(days: i + 1)),
          summary: 'Chat',
          medium: 'Call',
        ),
    ],
  );
}

void main() {
  late _TestDBHelper dbHelper;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dbHelper = _TestDBHelper();
    DBHelper.overrideForTest(dbHelper);
  });

  tearDown(() {
    DBHelper.resetTestOverride();
  });

  Future<void> pumpReview(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders period chips, verdict, and marks', (tester) async {
    // Already a regular contact before this month; logs again without
    // advancing anyone → attention verdict.
    dbHelper.contacts.add(_contact('c1', 'Bob Jones', 3, monthsAgo: 2));

    await pumpReview(tester);

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Semester'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    // No confirmed moves → attention verdict.
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('Movement'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Marks'), findsOneWidget);
    expect(
        find.textContaining('No one reached regular contact'), findsOneWidget);
    expect(find.text('Intention'), findsOneWidget);
    expect(find.text('Care'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('What didn\'t happen'), findsOneWidget);
  });

  testWidgets('confirmed moves drive the movement story', (tester) async {
    final now = DateTime.now();
    dbHelper.contacts.add(
      _contact('c1', 'Alice Smith', 3, stage: 'Second contact'),
    );
    dbHelper.stageMoves.add(
      StageMove(
        contactId: 'c1',
        fromStage: 'Second contact',
        toStage: 'Regular contact',
        movedAt: DateTime(now.year, now.month, 5),
      ),
    );

    await pumpReview(tester);

    expect(find.text('GOOD MONTH'), findsOneWidget);
    expect(find.textContaining('became a regular contact'), findsWidgets);

    // Switching periods keeps the page functional.
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('renders the empty movement state when nobody advanced',
      (tester) async {
    dbHelper.contacts.addAll([
      _contact('c1', 'Abe', 0),
      _contact('c2', 'Bea', 0),
    ]);

    await pumpReview(tester);

    expect(find.text('No stage changes recorded this month.'), findsOneWidget);
  });

  testWidgets('suggests stage changes and confirms them', (tester) async {
    // 2 interactions justify Second contact, but the stage is pinned lower.
    dbHelper.contacts
        .add(_contact('c1', 'Gus Hall', 2, stage: 'First contact'));

    await pumpReview(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Confirm stage changes'), findsOneWidget);
    expect(find.text('Gus Hall'), findsOneWidget);
    expect(find.text('First contact → Second contact'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // After confirming, the stage matches the activity → no more suggestions.
    expect(dbHelper.contacts.single.stage, 'Second contact');
    expect(dbHelper.stageMoves, hasLength(1));
    expect(find.text('Confirm stage changes'), findsNothing);
  });

  testWidgets('dismissing a suggestion removes it', (tester) async {
    dbHelper.contacts
        .add(_contact('c1', 'Gus Hall', 2, stage: 'First contact'));

    await pumpReview(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm stage changes'), findsNothing);
    expect(dbHelper.stageMoves, isEmpty);
  });
}
