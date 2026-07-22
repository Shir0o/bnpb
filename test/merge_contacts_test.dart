import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/models/relationship.dart';
import 'package:bnpb/screens/import_duplicate_review_page.dart';

PrayerRequest _request({
  required String syncId,
  required List<String> participantIds,
}) {
  return PrayerRequest(
    syncId: syncId,
    participantIds: participantIds,
    description: 'desc',
    status: PrayerRequestStatus.pending,
    requestedAt: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}

Interaction _interaction({
  required String syncId,
  required List<String> participantIds,
}) {
  return Interaction(
    syncId: syncId,
    occurredAt: DateTime.parse('2026-01-02T00:00:00Z'),
    summary: 'coffee',
    medium: 'in_person',
    participantIds: participantIds,
  );
}

void main() {
  test(
    'mergeContacts rewrites participantIds in interactions to primary.id',
    () {
      final primary = Contact(
        id: 'A',
        firstName: 'Robert',
        lastName: 'Smith',
        interactions: [
          _interaction(syncId: 'i-1', participantIds: ['A']),
        ],
      );
      final secondary = Contact(
        id: 'B',
        firstName: 'Bob',
        lastName: 'Smith',
        interactions: [
          _interaction(syncId: 'i-2', participantIds: ['B', 'C']),
        ],
      );

      final merged = mergeContacts([primary, secondary]);

      expect(merged.id, 'A');
      final byId = {for (final x in merged.interactions) x.syncId: x};
      expect(byId['i-1']!.participantIds, ['A']);
      // 'B' is rewritten to 'A'; outside reference 'C' is preserved.
      expect(byId['i-2']!.participantIds, ['A', 'C']);
    },
  );

  test('mergeContacts rewrites participantIds in prayer requests', () {
    final primary = Contact(id: 'A', firstName: 'Robert', lastName: 'Smith');
    final secondary = Contact(
      id: 'B',
      firstName: 'Bob',
      lastName: 'Smith',
      prayerRequests: [
        _request(syncId: 'p-1', participantIds: ['B']),
        _request(syncId: 'p-2', participantIds: ['B', 'X']),
      ],
    );

    final merged = mergeContacts([primary, secondary]);

    final byId = {for (final p in merged.prayerRequests) p.syncId: p};
    expect(byId['p-1']!.participantIds, ['A']);
    expect(byId['p-2']!.participantIds, ['A', 'X']);
  });

  test(
    'mergeContacts rewrites relationship endpoints and drops self-edges',
    () {
      final primary = Contact(
        id: 'A',
        firstName: 'Robert',
        lastName: 'Smith',
        relationships: [
          Relationship(
            sourceContactId: 'A',
            targetContactId: 'B', // would become A->A after merge
            type: 'friend',
          ),
        ],
      );
      final secondary = Contact(
        id: 'B',
        firstName: 'Bob',
        lastName: 'Smith',
        relationships: [
          Relationship(
            sourceContactId: 'B',
            targetContactId: 'X', // should rewrite source to A
            type: 'mentor',
          ),
        ],
      );

      final merged = mergeContacts([primary, secondary]);

      expect(merged.relationships, hasLength(1));
      final kept = merged.relationships.first;
      expect(kept.sourceContactId, 'A');
      expect(kept.targetContactId, 'X');
      expect(kept.type, 'mentor');
    },
  );

  test('mergeContacts dedupes interactions/prayer requests by syncId', () {
    final shared = _interaction(syncId: 'i-shared', participantIds: ['A']);
    final primary = Contact(
      id: 'A',
      firstName: 'Robert',
      lastName: 'Smith',
      interactions: [shared],
    );
    final secondary = Contact(
      id: 'B',
      firstName: 'Bob',
      lastName: 'Smith',
      // same syncId — must collapse to a single entry
      interactions: [
        _interaction(syncId: 'i-shared', participantIds: ['B']),
      ],
    );

    final merged = mergeContacts([primary, secondary]);

    expect(merged.interactions, hasLength(1));
  });

  test(
    'mergeContacts fills optional fields from the first non-empty value',
    () {
      final primary = Contact(id: 'A', firstName: 'Robert', lastName: 'Smith');
      final secondary = Contact(
        id: 'B',
        firstName: 'Bob',
        lastName: 'Smith',
        email: 'bob@example.com',
        phone: '5550100',
        notes: 'from secondary',
      );

      final merged = mergeContacts([primary, secondary]);

      expect(merged.id, 'A');
      expect(merged.email, 'bob@example.com');
      expect(merged.phone, '5550100');
      expect(merged.notes, 'from secondary');
    },
  );
}
