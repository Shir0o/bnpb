import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/contact_search_service.dart';

void main() {
  test('general search matches dietary preference text', () {
    final contact = Contact(
      id: 'contact-1',
      firstName: 'Jordan',
      dietaryPreference: 'Gluten free meals only',
    );

    final service = ContactSearchService();
    service.index([contact]);

    final results = service.search('gluten');

    expect(results, isNotEmpty);
    final match = results.first;
    expect(match.contact.id, contact.id);
    expect(match.matchDescription, 'Dietary preferences');
    expect(match.snippet, contains('Gluten free meals only'));
  });

  test('meeting context search surfaces dietary preferences', () {
    final contact = Contact(
      id: 'contact-2',
      firstName: 'Marin',
      dietaryPreference: 'Severe nut allergy',
    );

    final service = ContactSearchService();
    service.index([contact]);

    final results = service.searchMeetingContexts('nut');

    expect(results, isNotEmpty);
    final match = results.first;
    expect(match.contact.id, contact.id);
    expect(match.matchDescription, 'Dietary preferences');
    expect(match.snippet, contains('Severe nut allergy'));
  });
}
