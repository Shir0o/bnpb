import 'package:bnpb/db/daos/prayer_list_dao.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/screens/prayer_lists_page.dart';
import 'package:bnpb/widgets/add_people_to_prayer_list_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDBHelper extends Mock implements DBHelper {}

class MockPrayerListDao extends Mock implements PrayerListDao {}

void main() {
  late MockDBHelper db;
  late MockPrayerListDao dao;
  final alice = Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith');
  final bob = Contact(id: 'c2', firstName: 'Bob', lastName: 'Jones');

  setUp(() {
    db = MockDBHelper();
    dao = MockPrayerListDao();
    when(() => db.prayerListDao).thenReturn(dao);
    when(() => dao.getAllPrayerListContactIds())
        .thenAnswer((_) async => ['c1']);
    when(() => db.getContacts(contactIds: any(named: 'contactIds')))
        .thenAnswer((_) async => [alice]);
    when(() => db.getContacts()).thenAnswer((_) async => [alice, bob]);
    when(
      () => db.getPrayerRequests(status: any(named: 'status')),
    ).thenAnswer(
      (_) async => [
        PrayerRequest(
          participantIds: ['c1'],
          description: 'Healing',
          status: PrayerRequestStatus.pending,
          requestedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    when(() => dao.addContactsToDefaultList(any())).thenAnswer((_) async {});
  });

  testWidgets('shows merged members with latest open request', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PrayerListPage(dbHelper: db)));
    await tester.pumpAndSettle();

    expect(find.text('1 person'), findsOneWidget);
    expect(find.text('Alice Smith'), findsOneWidget);
    expect(find.text('Healing'), findsOneWidget);
    expect(find.text('1 open'), findsOneWidget);
  });

  testWidgets('add sheet greys members and returns selection', (tester) async {
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await AddPeopleToPrayerListSheet.show(
              context,
              onListIds: {'c1'},
              dbHelper: db,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('On list'), findsOneWidget);
    expect(find.text('Select people to add'), findsOneWidget);

    await tester.tap(find.text('Alice Smith'));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);

    await tester.tap(find.text('Bob Jones'));
    await tester.pump();
    expect(find.text('Add 1 person'), findsOneWidget);

    await tester.tap(find.text('Add 1 person'));
    await tester.pumpAndSettle();
    expect(result, ['c2']);
  });
}
