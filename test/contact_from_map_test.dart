import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';

void main() {
  test('fromMap generates an id when missing', () {
    final contact = Contact.fromMap({'firstName': 'Alice'});

    expect(contact.firstName, 'Alice');
    expect(contact.id, isNotEmpty);
  });

  test('fromMap preserves provided id', () {
    final contact = Contact.fromMap({
      'id': 'contact-123',
      'firstName': 'Bob',
    });

    expect(contact.firstName, 'Bob');
    expect(contact.id, 'contact-123');
  });

  test('fromMap captures dietary preference', () {
    final contact = Contact.fromMap({
      'id': 'contact-456',
      'firstName': 'Chris',
      'dietaryPreference': 'Vegetarian',
    });

    expect(contact.dietaryPreference, 'Vegetarian');
  });
}
