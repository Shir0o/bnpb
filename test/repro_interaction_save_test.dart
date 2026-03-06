import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/screens/contact_details_page.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MockContactService extends Mock implements ContactService {}

class MockDBHelper extends Mock implements DBHelper {
  @override
  Future<Database> get database async => throw UnimplementedError();
}

void main() {
  late MockContactService mockContactService;
  late MockDBHelper mockDBHelper;

  setUpAll(() async {
    await initializeDateFormatting('en_US', null);
  });

  setUp(() {
    mockContactService = MockContactService();
    mockDBHelper = MockDBHelper();

    registerFallbackValue(Contact(id: 'fake', firstName: 'Fake'));
    registerFallbackValue(
      Interaction(occurredAt: DateTime.now(), summary: 'fake', medium: 'call'),
    );
  });

  testWidgets('Saving a new interaction updates the UI list', (
    WidgetTester tester,
  ) async {
    final contact = Contact(id: 'c1', firstName: 'John');

    when(
      () => mockContactService.getInteractions(
        'c1',
        forceRefresh: any(named: 'forceRefresh'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => mockContactService.hasCachedInteractions('c1'),
    ).thenReturn(false);

    when(() => mockDBHelper.getContacts()).thenAnswer((_) async => []);
    when(
      () => mockDBHelper.getRelationshipsForContact('c1'),
    ).thenAnswer((_) async => []);
    when(() => mockDBHelper.getAllTags()).thenAnswer((_) async => []);

    // Stub for inserting interaction
    when(() => mockDBHelper.insertInteraction(any())).thenAnswer((
      invocation,
    ) async {
      final interaction = invocation.positionalArguments[0] as Interaction;
      return interaction.copyWith(id: 1);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ContactDetailsPage(
          contact: contact,
          onDelete: () async {},
          contactService: mockContactService,
          dbHelper: mockDBHelper,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Find the "Log interaction" button (FAB or similar)
    // Actually, it's a "Log interaction" button in the sliver list probably
    // Or let's just trigger _showQuickAddInteractionSheet directly if possible,
    // but better to use the UI.

    // In ContactDetailsPage, there's a floating action button for quick log?
    // Let's check the build method for FAB.
  });
}
