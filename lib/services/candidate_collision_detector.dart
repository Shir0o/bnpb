import '../models/candidate_interaction.dart';
import '../models/interaction.dart';

/// Detects collisions and potential duplicates between incoming
/// [CandidateInteraction]s and existing database [Interaction]s.
class CandidateCollisionDetector {
  /// Compares [candidates] against [existingInteractions] within [windowDuration]
  /// (default 60 minutes).
  ///
  /// If an existing interaction shares at least one participant OR shares
  /// an activity keyword within the time window, the candidate is flagged
  /// with [possibleDuplicateOf] and [duplicateReason], and defaulted to
  /// `selected = false`.
  static List<CandidateInteraction> detectCollisions({
    required List<CandidateInteraction> candidates,
    required List<Interaction> existingInteractions,
    Duration windowDuration = const Duration(minutes: 60),
  }) {
    if (candidates.isEmpty || existingInteractions.isEmpty) {
      return candidates;
    }

    final result = <CandidateInteraction>[];

    for (final candidate in candidates) {
      Interaction? matchedDuplicate;
      String? reason;

      for (final existing in existingInteractions) {
        final timeDiff =
            candidate.occurredAt.difference(existing.occurredAt).abs();
        if (timeDiff <= windowDuration) {
          // Check shared contacts
          final commonContacts = candidate.matchedContactIds
              .where((cId) => existing.participantIds.contains(cId))
              .toList();

          if (commonContacts.isNotEmpty) {
            matchedDuplicate = existing;
            final minDiff = timeDiff.inMinutes;
            reason =
                'Matches interaction "${existing.summary}" ($minDiff min apart)';
            break;
          }

          // Check identical/similar summary if no contacts were matched yet
          if (candidate.matchedContactIds.isEmpty &&
              candidate.summary.trim().isNotEmpty &&
              existing.summary.trim().toLowerCase() ==
                  candidate.summary.trim().toLowerCase()) {
            matchedDuplicate = existing;
            reason =
                'Same summary "${existing.summary}" (${timeDiff.inMinutes} min apart)';
            break;
          }
        }
      }

      if (matchedDuplicate != null) {
        result.add(
          candidate.copyWith(
            possibleDuplicateOf: matchedDuplicate.id?.toString(),
            duplicateReason: reason,
            selected: false,
          ),
        );
      } else {
        result.add(candidate);
      }
    }

    return result;
  }
}
