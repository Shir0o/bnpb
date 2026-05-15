import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/import_duplicate_detector.dart';

Contact _contact({
  required String id,
  required String firstName,
  String? lastName,
  String? nickname,
  String? phone,
  String? email,
}) {
  return Contact(
    id: id,
    firstName: firstName,
    lastName: lastName,
    nickname: nickname,
    phone: phone,
    email: email,
  );
}

void main() {
  final detector = ImportDuplicateDetector();

  test('flags nothing for an empty or single-contact list', () {
    expect(detector.findDuplicateGroups(const []), isEmpty);
    expect(
      detector.findDuplicateGroups([
        _contact(id: '1', firstName: 'Ada', lastName: 'Lovelace'),
      ]),
      isEmpty,
    );
  });

  test('does NOT flag siblings sharing only a surname', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'Alice', lastName: 'Smith'),
      _contact(id: '2', firstName: 'Bob', lastName: 'Smith'),
      _contact(id: '3', firstName: 'Carol', lastName: 'Smith'),
    ]);
    expect(groups, isEmpty);
  });

  test('flags exact-name duplicates', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'Bob', lastName: 'Smith'),
      _contact(id: '2', firstName: 'Bob', lastName: 'Smith'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.first.members.map((c) => c.id), ['1', '2']);
  });

  test('flags near-name duplicates via trigram similarity', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'Jonathan', lastName: 'Smith'),
      _contact(id: '2', firstName: 'Johnathan', lastName: 'Smith'),
    ]);
    expect(groups, hasLength(1));
  });

  test('flags nickname expansion (Bob <-> Robert) when surnames match', () {
    final groups = detector.findDuplicateGroups([
      _contact(
          id: '1', firstName: 'Robert', lastName: 'Smith', nickname: 'Bob'),
      _contact(id: '2', firstName: 'Bob', lastName: 'Smith'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.first.reason.toLowerCase(), contains('nickname'));
  });

  test('flags shared phone number across different formats', () {
    final groups = detector.findDuplicateGroups([
      _contact(
          id: '1', firstName: 'Jane', lastName: 'Doe', phone: '(415) 555-0199'),
      _contact(id: '2', firstName: 'J.', lastName: 'D.', phone: '4155550199'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.first.reason.toLowerCase(), contains('phone'));
  });

  test('flags shared phone with country code variations', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'Sam', phone: '+1 415-555-0199'),
      _contact(id: '2', firstName: 'Samantha', phone: '415.555.0199'),
    ]);
    expect(groups, hasLength(1));
  });

  test('flags shared email case-insensitively', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'A', email: 'Foo@Example.com'),
      _contact(id: '2', firstName: 'B', email: 'foo@example.com  '),
    ]);
    expect(groups, hasLength(1));
    expect(groups.first.reason.toLowerCase(), contains('email'));
  });

  test('groups transitively via union-find', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'Robert', lastName: 'Smith'),
      _contact(
          id: '2', firstName: 'Robert', lastName: 'Smith', phone: '5550100'),
      _contact(id: '3', firstName: 'Z', phone: '5550100'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.first.members.map((c) => c.id).toSet(), {'1', '2', '3'});
  });

  test('does not flag unrelated contacts', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'Alice', lastName: 'Smith', phone: '111'),
      _contact(id: '2', firstName: 'Bob', lastName: 'Jones', phone: '222'),
      _contact(
          id: '3', firstName: 'Carol', lastName: 'Brown', email: 'c@x.com'),
    ]);
    expect(groups, isEmpty);
  });

  test('ignores empty phone and empty email when grouping', () {
    final groups = detector.findDuplicateGroups([
      _contact(id: '1', firstName: 'A', lastName: 'X', phone: '', email: ''),
      _contact(id: '2', firstName: 'B', lastName: 'Y', phone: '', email: ''),
    ]);
    expect(groups, isEmpty);
  });
}
