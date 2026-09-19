import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/candidate_interaction.dart';
import '../../models/contact.dart';
import 'ai_services.dart';

/// Resolves ambiguous or unmatched candidate interactions using the active AI backend.
class TimeTrackerAiResolver {
  final AiServices _aiServices;

  TimeTrackerAiResolver({AiServices? aiServices})
      : _aiServices = aiServices ?? AiServices();

  /// Prompts the LLM to map [candidate] to one or more [contacts] based on its [rawComment] and [activityName].
  Future<List<String>> resolveContactsForCandidate({
    required CandidateInteraction candidate,
    required List<Contact> contacts,
  }) async {
    if (!_aiServices.llm.isReady || contacts.isEmpty) return [];

    final contactListStr = contacts
        .map((c) => '{"id": "${c.id}", "name": "${c.displayName}"}')
        .join(',\n');

    final prompt = '''
You are an assistant matching a user's logged activity to their private contact list.
Given an activity comment: "${candidate.rawComment.isNotEmpty ? candidate.rawComment : candidate.activityName}"

And this list of available contacts:
[
$contactListStr
]

Identify which contacts from the list were present or mentioned in this activity comment.
Respond with ONLY a JSON array of matching contact id strings, e.g. ["id1", "id2"].
If no contacts match, return []. Do not include markdown codeblocks or other commentary.
''';

    try {
      final response = await _aiServices.llm.generate(prompt);
      final clean = response.replaceAll(RegExp(r'```json|```'), '').trim();
      final decoded = jsonDecode(clean);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((id) => contacts.any((c) => c.id == id))
            .toList();
      }
    } catch (e) {
      debugPrint('TimeTrackerAiResolver error: $e');
    }

    return [];
  }
}
