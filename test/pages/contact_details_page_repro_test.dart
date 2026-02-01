import 'package:bnpb/db/db_helper.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/screens/contact_details_page.dart';
import 'package:bnpb/services/contact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

class MockContactService extends Mock implements ContactService {
  @override
  bool hasCachedInteractions(String? contactId) => false;

  @override
  Future<List<Interaction>> getInteractions(String? contactId,
      {bool forceRefresh = false}) async {
    return [];
  }
  
  @override
  void invalidateInteractions(String? contactId) {}
}

class MockDBHelper extends Mock implements DBHelper {
  @override
  Future<List<Contact>> getContacts({String? contactId}) async {
    return [];
  }

  @override
  Future<List<String>> getAllTags() async {
    return [];
  }

  @override
  Future<List<Relationship>> getRelationshipsForContact(String? contactId) async {
    return [];
  }
}

void main() {
  testWidgets('ContactDetailsPage renders contact details correctly',
      (WidgetTester tester) async {
    final contact = Contact(
      id: '123',
      firstName: 'John',
      lastName: 'Doe',
      nickname: 'Johnny',
      location: 'New York',
      notes: 'Some notes',
      interactions: [],
    );

    final mockContactService = MockContactService();
    final mockDBHelper = MockDBHelper();

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

    // Initial load skeleton
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for async load to complete
    await tester.pumpAndSettle();

    // Verify fields are populated
    expect(find.text('John Doe'), findsOneWidget); // AppBar title / PeopleCard
    expect(find.text('New York'), findsOneWidget);
    expect(find.text('Johnny'), findsOneWidget);
    expect(find.text('Some notes'), findsOneWidget);

    // Verify that we are NOT in edit mode
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });
} 
