import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/widgets/prayer_diary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 3, 9);

PrayerRequest _request({
  PrayerRequestStatus status = PrayerRequestStatus.pending,
  DateTime? answeredAt,
  DateTime? archivedAt,
  String? notes,
}) =>
    PrayerRequest(
      id: 1,
      participantIds: const ['c1'],
      description: 'Recovery after knee surgery',
      status: status,
      requestedAt: DateTime(2026, 11, 1),
      answeredAt: answeredAt,
      archivedAt: archivedAt,
      category: 'Health',
      reflectionNotes: notes,
    );

class _Calls {
  int prayed = 0;
  final statuses = <(PrayerRequestStatus, String?)>[];
}

Future<_Calls> _pump(
  WidgetTester tester,
  PrayerRequest request, {
  List<DateTime> prayed = const [],
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PrayerDiaryCard(
            request: request,
            names: 'Grace Liu',
            initials: 'GL',
            prayedDates: prayed,
            now: _now,
            onOpen: () {},
            onTogglePrayed: () => calls.prayed++,
            onSetStatus: (status, comment) async =>
                calls.statuses.add((status, comment)),
          ),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  testWidgets('pending card shows record, meta and the three actions', (
    tester,
  ) async {
    final calls = await _pump(tester, _request());

    expect(find.text('Praying'), findsOneWidget);
    expect(find.text('Health · requested Nov 1'), findsOneWidget);
    expect(find.text('Not prayed for yet'), findsOneWidget);

    await tester.tap(find.text('Prayed'));
    expect(calls.prayed, 1);
    expect(find.text('Answered'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('prayed today fills the button and summarises the record', (
    tester,
  ) async {
    await _pump(
      tester,
      _request(),
      prayed: [DateTime(2026, 10, 28), DateTime(2026, 11, 1), _now],
    );

    expect(find.text('Prayed today'), findsOneWidget);
    expect(find.text('Prayed 3× · today'), findsOneWidget);
    expect(find.text('Oct 28 · Nov 1 · Nov 3'), findsOneWidget);
  });

  testWidgets('earlier record shows the last date and last three days', (
    tester,
  ) async {
    await _pump(
      tester,
      _request(),
      prayed: [
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 27),
        DateTime(2026, 10, 31),
      ],
    );

    expect(find.text('Prayed'), findsOneWidget);
    expect(find.text('Prayed 4× · last Oct 31'), findsOneWidget);
    expect(find.text('Oct 24 · Oct 27 · Oct 31'), findsOneWidget);
  });

  testWidgets('Answered expands a comment field and confirms with it', (
    tester,
  ) async {
    final calls = await _pump(tester, _request());

    await tester.tap(find.text('Answered'));
    await tester.pump();
    expect(find.text('How was it answered?'), findsOneWidget);
    expect(find.text('Prayed'), findsNothing);

    await tester.enterText(find.byType(TextField), '  Surgery went well  ');
    await tester.tap(find.text('Mark answered'));
    await tester.pump();

    expect(
        calls.statuses, [(PrayerRequestStatus.answered, 'Surgery went well')]);
  });

  testWidgets('Archive with a blank comment sends null; Cancel sends nothing', (
    tester,
  ) async {
    final calls = await _pump(tester, _request());

    await tester.tap(find.text('Archive'));
    await tester.pump();
    expect(find.text('Why archive it?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Why archive it?'), findsNothing);
    expect(calls.statuses, isEmpty);

    await tester.tap(find.text('Archive'));
    await tester.pump();
    // The confirm button shares the Archive label with the action it replaced.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Archive'));
    await tester.pump();
    expect(calls.statuses, [(PrayerRequestStatus.archived, null)]);
  });

  testWidgets('answered card shows its outcome and can be reopened', (
    tester,
  ) async {
    final calls = await _pump(
      tester,
      _request(
        status: PrayerRequestStatus.answered,
        answeredAt: DateTime(2026, 11, 2),
        notes: 'Moved to the final round',
      ),
    );

    expect(find.text('Answered Nov 2'), findsOneWidget);
    expect(find.text('Moved to the final round'), findsOneWidget);
    expect(find.text('Prayed'), findsNothing);

    await tester.tap(find.text('Reopen'));
    expect(calls.statuses, [(PrayerRequestStatus.pending, null)]);
  });

  testWidgets('archived card without a comment says so', (tester) async {
    await _pump(
      tester,
      _request(
        status: PrayerRequestStatus.archived,
        archivedAt: DateTime(2026, 10, 20),
      ),
    );

    expect(find.text('Archived Oct 20'), findsOneWidget);
    expect(find.text('No comment'), findsOneWidget);
  });
}
