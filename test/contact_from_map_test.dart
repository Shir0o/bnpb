import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';

void main() {
  test('fromMap generates an id when missing', () {
    final contact = Contact.fromMap({'firstName': 'Alice'});

    expect(contact.firstName, 'Alice');
    expect(contact.id, isNotEmpty);
  });
}
