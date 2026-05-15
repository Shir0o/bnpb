import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/ai/semantic_search_service.dart';

Contact _contact({
  required String id,
  required String firstName,
  List<Interaction>? interactions,
  List<PrayerRequest>? prayerRequests,
  DateTime? deletedAt,
}) {
  return Contact(
    id: id,
    firstName: firstName,
    interactions: interactions,
    prayerRequests: prayerRequests,
    deletedAt: deletedAt,
  );
}

Interaction _interaction({
  required String syncId,
  String summary = 'Coffee chat',
  String? notes,
  String? location,
  DateTime? deletedAt,
}) {
  return Interaction(
    syncId: syncId,
    occurredAt: DateTime.utc(2026, 3, 15),
    summary: summary,
    medium: 'in_person',
    notes: notes,
    location: location,
    deletedAt: deletedAt,
  );
}

PrayerRequest _request({
  required String syncId,
  required String contactId,
  String description = 'Pray for job hunting',
  String? reflectionNotes,
  DateTime? deletedAt,
}) {
  return PrayerRequest(
    syncId: syncId,
    participantIds: [contactId],
    description: description,
    status: PrayerRequestStatus.pending,
    requestedAt: DateTime.utc(2026, 3, 1),
    reflectionNotes: reflectionNotes,
    deletedAt: deletedAt,
  );
}

void main() {
  group('documentsFor', () {
    test('emits one document per interaction and one per prayer request', () {
      final contacts = [
        _contact(
          id: 'c1',
          firstName: 'Ada',
          interactions: [_interaction(syncId: 'i-1')],
          prayerRequests: [_request(syncId: 'p-1', contactId: 'c1')],
        ),
      ];

      final docs = documentsFor(contacts);

      expect(docs, hasLength(2));
      expect(docs.map((d) => d.id).toSet(), {'interaction:i-1', 'prayer:p-1'});
      final byType = {for (final d in docs) d.type: d};
      expect(byType[IndexDocumentType.interaction]!.contactId, 'c1');
      expect(byType[IndexDocumentType.prayerRequest]!.contactId, 'c1');
    });

    test('skips soft-deleted contacts', () {
      final docs = documentsFor([
        _contact(
          id: 'c1',
          firstName: 'Ada',
          interactions: [_interaction(syncId: 'i-1')],
          deletedAt: DateTime.utc(2026, 4, 1),
        ),
      ]);
      expect(docs, isEmpty);
    });

    test('skips soft-deleted interactions and prayer requests', () {
      final docs = documentsFor([
        _contact(
          id: 'c1',
          firstName: 'Ada',
          interactions: [
            _interaction(syncId: 'i-1', deletedAt: DateTime.utc(2026, 4, 1)),
            _interaction(syncId: 'i-2'),
          ],
          prayerRequests: [
            _request(
                syncId: 'p-1',
                contactId: 'c1',
                deletedAt: DateTime.utc(2026, 4, 1)),
          ],
        ),
      ]);
      expect(docs.map((d) => d.id), ['interaction:i-2']);
    });

    test('drops items with no embeddable text', () {
      final docs = documentsFor([
        _contact(
          id: 'c1',
          firstName: 'Ada',
          interactions: [
            _interaction(
                syncId: 'i-empty', summary: '', location: '', notes: ''),
          ],
          prayerRequests: [
            _request(syncId: 'p-empty', contactId: 'c1', description: ''),
          ],
        ),
      ]);
      expect(docs, isEmpty);
    });

    test('combines summary, notes, location into the embedded content', () {
      final docs = documentsFor([
        _contact(
          id: 'c1',
          firstName: 'Ada',
          interactions: [
            _interaction(
              syncId: 'i-1',
              summary: 'Coffee chat',
              location: 'Sightglass',
              notes: 'talked about new role',
            ),
          ],
        ),
      ]);
      expect(docs.single.content, contains('Coffee chat'));
      expect(docs.single.content, contains('Sightglass'));
      expect(docs.single.content, contains('new role'));
    });
  });

  group('IndexDocument metadata round-trip', () {
    test('encodes and decodes contactId + type', () {
      final doc = IndexDocument(
        id: 'interaction:abc',
        content: 'x',
        contactId: 'c1',
        type: IndexDocumentType.prayerRequest,
      );
      final encoded = doc.toMetadata();
      final json =
          '{"contactId":"${encoded['contactId']}","type":"${encoded['type']}"}';
      expect(IndexDocument.contactIdFromMetadata(json), 'c1');
      expect(IndexDocument.typeFromMetadata(json),
          IndexDocumentType.prayerRequest);
    });

    test('tolerates missing or malformed metadata', () {
      expect(IndexDocument.contactIdFromMetadata(null), isNull);
      expect(IndexDocument.contactIdFromMetadata('not json'), isNull);
      expect(IndexDocument.typeFromMetadata(null), isNull);
    });
  });

  group('resultsToMatches', () {
    test('joins on contactId and preserves rank order', () {
      final contacts = {
        'c1': _contact(id: 'c1', firstName: 'Ada'),
        'c2': _contact(id: 'c2', firstName: 'Linus'),
      };
      final results = [
        RetrievalResult(
          id: 'interaction:i-1',
          content: 'Coffee with Ada',
          similarity: 0.91,
          metadata: '{"contactId":"c1","type":"interaction"}',
        ),
        RetrievalResult(
          id: 'prayer:p-1',
          content: 'Pray for Linus',
          similarity: 0.78,
          metadata: '{"contactId":"c2","type":"prayerRequest"}',
        ),
      ];

      final matches = resultsToMatches(results, contacts);

      expect(matches.map((m) => m.contact.id), ['c1', 'c2']);
      expect(matches[0].type, IndexDocumentType.interaction);
      expect(matches[1].type, IndexDocumentType.prayerRequest);
      expect(matches[0].score, 0.91);
    });

    test('drops results whose contactId is no longer present', () {
      final contacts = {'c1': _contact(id: 'c1', firstName: 'Ada')};
      final results = [
        RetrievalResult(
          id: 'interaction:gone',
          content: '...',
          similarity: 0.9,
          metadata: '{"contactId":"c-gone","type":"interaction"}',
        ),
        RetrievalResult(
          id: 'interaction:i-1',
          content: 'hi',
          similarity: 0.5,
          metadata: '{"contactId":"c1","type":"interaction"}',
        ),
      ];

      final matches = resultsToMatches(results, contacts);

      expect(matches.map((m) => m.contact.id), ['c1']);
    });

    test('drops results with no metadata', () {
      final contacts = {'c1': _contact(id: 'c1', firstName: 'Ada')};
      final results = [
        RetrievalResult(
          id: 'orphan',
          content: '...',
          similarity: 0.9,
          metadata: null,
        ),
      ];
      expect(resultsToMatches(results, contacts), isEmpty);
    });
  });
}
