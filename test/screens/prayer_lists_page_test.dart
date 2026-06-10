import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/screens/prayer_lists_page.dart';

class MockDBHelper extends Mock implements DBHelper {}

void main() {
  group('PrayerListPage Widget Tests', () {
    late MockDBHelper mockDBHelper;

    setUp(() {
      mockDBHelper = MockDBHelper();
    });

    testWidgets(
        'displays contacts, has no remove icon, removes contact on swipe, and undoes removal',
        (WidgetTester tester) async {
      final contact1 = Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith');
      final contact2 = Contact(id: 'c2', firstName: 'Bob', lastName: 'Jones');

      final list = PrayerList(
        id: 'list-123',
        name: 'My Prayer List',
        description: 'People I am praying for',
        contactIds: ['c1', 'c2'],
      );

      // State variable to simulate database member list
      var currentContactIds = ['c1', 'c2'];

      // Stub methods called during initialization
      when(() => mockDBHelper.getPrayerLists()).thenAnswer((_) async => [list]);
      when(() => mockDBHelper.getPrayerList('list-123')).thenAnswer((_) async {
        return PrayerList(
          id: 'list-123',
          name: 'My Prayer List',
          description: 'People I am praying for',
          contactIds: currentContactIds,
        );
      });
      when(() => mockDBHelper.getContacts(contactIds: any(named: 'contactIds')))
          .thenAnswer((invocation) async {
        final ids = invocation.namedArguments[const Symbol('contactIds')]
            as List<String>?;
        final list = <Contact>[];
        if (ids != null) {
          if (ids.contains('c1')) list.add(contact1);
          if (ids.contains('c2')) list.add(contact2);
        }
        return list;
      });

      // Stub remove contact
      when(() => mockDBHelper.removeContactFromPrayerList('list-123', 'c1'))
          .thenAnswer((_) async {
        currentContactIds = ['c2'];
      });

      // Stub add contact (undo)
      when(() => mockDBHelper.addContactToPrayerList('list-123', 'c1'))
          .thenAnswer((_) async {
        currentContactIds = ['c1', 'c2'];
      });

      // 2. Pump the widget with injected MockDBHelper
      await tester.pumpWidget(
        MaterialApp(
          home: PrayerListPage(dbHelper: mockDBHelper),
        ),
      );

      // Wait for loading futures and delay (300ms) to complete.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 3. Verify contacts are displayed
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsOneWidget);

      // 4. Verify that the trailing remove icon is NOT present
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      // 5. Swipe left on Alice Smith
      await tester.fling(
          find.text('Alice Smith'), const Offset(-500.0, 0.0), 1000.0);
      await tester.pumpAndSettle();

      // Verify SnackBar is shown and Alice is removed from UI
      expect(find.text('Alice Smith'), findsNothing);
      expect(find.text('Bob Jones'), findsOneWidget);
      expect(find.text('Removed Alice Smith from list'), findsOneWidget);
      expect(find.text('UNDO'), findsOneWidget);

      // 6. Click UNDO to restore
      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();

      // Verify Alice Smith is back
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsOneWidget);
    });

    testWidgets('clears snackbar when the page is disposed/popped',
        (WidgetTester tester) async {
      final contact1 = Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith');
      var currentContactIds = ['c1'];

      when(() => mockDBHelper.getPrayerLists()).thenAnswer((_) async => [
            PrayerList(
              id: 'list-123',
              name: 'My Prayer List',
              description: 'People I am praying for',
              contactIds: ['c1'],
            )
          ]);
      when(() => mockDBHelper.getPrayerList('list-123')).thenAnswer((_) async {
        return PrayerList(
          id: 'list-123',
          name: 'My Prayer List',
          description: 'People I am praying for',
          contactIds: currentContactIds,
        );
      });
      when(() => mockDBHelper.getContacts(contactIds: any(named: 'contactIds')))
          .thenAnswer((invocation) async {
        final ids = invocation.namedArguments[const Symbol('contactIds')]
            as List<String>?;
        final list = <Contact>[];
        if (ids != null && ids.contains('c1')) {
          list.add(contact1);
        }
        return list;
      });
      when(() => mockDBHelper.removeContactFromPrayerList('list-123', 'c1'))
          .thenAnswer((_) async {
        currentContactIds = [];
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PrayerListPage(dbHelper: mockDBHelper),
                    ),
                  );
                },
                child: const Text('Go to Prayer List'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go to Prayer List'));
      await tester.pumpAndSettle();

      await tester.fling(
          find.text('Alice Smith'), const Offset(-500.0, 0.0), 1000.0);
      await tester.pumpAndSettle();

      expect(find.text('Removed Alice Smith from list'), findsOneWidget);

      Navigator.of(tester.element(find.text('My Prayer List'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('Removed Alice Smith from list'), findsNothing);
    });

    testWidgets('clears snackbar when navigating to contact details',
        (WidgetTester tester) async {
      final contact1 = Contact(id: 'c1', firstName: 'Alice', lastName: 'Smith');
      final contact2 = Contact(id: 'c2', firstName: 'Bob', lastName: 'Jones');
      var currentContactIds = ['c1', 'c2'];

      when(() => mockDBHelper.getPrayerLists()).thenAnswer((_) async => [
            PrayerList(
              id: 'list-123',
              name: 'My Prayer List',
              description: 'People I am praying for',
              contactIds: ['c1', 'c2'],
            )
          ]);
      when(() => mockDBHelper.getPrayerList('list-123')).thenAnswer((_) async {
        return PrayerList(
          id: 'list-123',
          name: 'My Prayer List',
          description: 'People I am praying for',
          contactIds: currentContactIds,
        );
      });
      when(() => mockDBHelper.getContacts(contactIds: any(named: 'contactIds')))
          .thenAnswer((invocation) async {
        final ids = invocation.namedArguments[const Symbol('contactIds')]
            as List<String>?;
        final list = <Contact>[];
        if (ids != null) {
          if (ids.contains('c1')) list.add(contact1);
          if (ids.contains('c2')) list.add(contact2);
        }
        return list;
      });
      when(() => mockDBHelper.removeContactFromPrayerList('list-123', 'c1'))
          .thenAnswer((_) async {
        currentContactIds = ['c2'];
      });

      bool navigatedToDetails = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PrayerListPage(
            dbHelper: mockDBHelper,
            onNavigateToContactDetails: (context, contact) {
              navigatedToDetails = true;
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      await tester.fling(
          find.text('Alice Smith'), const Offset(-500.0, 0.0), 1000.0);
      await tester.pumpAndSettle();

      expect(find.text('Removed Alice Smith from list'), findsOneWidget);

      await tester.tap(find.text('Bob Jones'));
      await tester.pumpAndSettle();

      expect(navigatedToDetails, isTrue);
      expect(find.text('Removed Alice Smith from list'), findsNothing);
    });
  });
}
