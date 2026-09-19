import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/candidate_collision_detector.dart';

void main() {
  group('CandidateCollisionDetector', () {
    final candidateTime = DateTime(2026, 6, 1, 14, 5, 0);

    test(
        'flags candidate as duplicate if existing interaction is within 60 min with overlapping contact',
        () {
      final candidate = CandidateInteraction(
        fingerprint: 'fp1',
        occurredAt: candidateTime,
        durationMinutes: 30,
        activityName: 'Lunch',
        summary: 'Lunch w/ Abel',
        matchedContactIds: ['c1'],
        rawComment: 'w/ Abel',
      );

      final existingInteraction = Interaction(
        id: 42,
        occurredAt: DateTime(2026, 6, 1, 14, 0, 0), // 5 min earlier
        summary: 'Coffee with Abel',
        medium: 'In Person',
        participantIds: ['c1'],
      );

      final checked = CandidateCollisionDetector.detectCollisions(
        candidates: [candidate],
        existingInteractions: [existingInteraction],
      );

      expect(checked.first.possibleDuplicateOf, '42');
      expect(checked.first.duplicateReason, isNotNull);
      expect(checked.first.selected, isFalse);
    });

    test(
        'does not flag candidate if existing interaction is outside window (> 60 min)',
        () {
      final candidate = CandidateInteraction(
        fingerprint: 'fp2',
        occurredAt: candidateTime,
        durationMinutes: 30,
        activityName: 'Lunch',
        summary: 'Lunch w/ Abel',
        matchedContactIds: ['c1'],
        rawComment: 'w/ Abel',
      );

      final existingInteraction = Interaction(
        id: 43,
        occurredAt: DateTime(2026, 6, 1, 11, 0, 0), // 3 hours earlier
        summary: 'Breakfast with Abel',
        medium: 'In Person',
        participantIds: ['c1'],
      );

      final checked = CandidateCollisionDetector.detectCollisions(
        candidates: [candidate],
        existingInteractions: [existingInteraction],
      );

      expect(checked.first.possibleDuplicateOf, isNull);
      expect(checked.first.selected, isTrue);
    });
  });
}
