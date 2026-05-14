import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/models/prayer_request.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:bnpb/services/ai/outreach_draft_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LocalLlmService {
  _FakeLlm({this.response = '', this.ready = true});
  String response;
  bool ready;
  String? lastPrompt;

  @override
  bool get isReady => ready;
  @override
  Future<void> load(String modelPath) async {}
  @override
  Future<void> unload() async {}
  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) async {
    lastPrompt = prompt;
    return response;
  }
}

Interaction _interaction({
  required String summary,
  String? notes,
  DateTime? occurredAt,
  DateTime? deletedAt,
}) {
  return Interaction(
    summary: summary,
    medium: 'in_person',
    notes: notes,
    occurredAt: occurredAt ?? DateTime(2026, 5, 14),
    deletedAt: deletedAt,
  );
}

PrayerRequest _prayer({
  required String description,
  PrayerRequestStatus status = PrayerRequestStatus.pending,
  DateTime? requestedAt,
  DateTime? deletedAt,
}) {
  return PrayerRequest(
    participantIds: const ['contact-1'],
    description: description,
    status: status,
    requestedAt: requestedAt ?? DateTime(2026, 5, 1),
    deletedAt: deletedAt,
  );
}

void main() {
  group('OutreachDraftService', () {
    test('throws when LLM is not ready', () async {
      final llm = _FakeLlm(ready: false);
      final svc = OutreachDraftService(llm);
      expect(
        () =>
            svc.suggestHooks(recentInteractions: [_interaction(summary: 'x')]),
        throwsA(isA<StateError>()),
      );
    });

    test('returns empty when there is no input', () async {
      final llm = _FakeLlm(response: 'unused');
      final svc = OutreachDraftService(llm);
      final out = await svc.suggestHooks(recentInteractions: const []);
      expect(out, isEmpty);
      expect(llm.lastPrompt, isNull);
    });

    test('parses a JSON array of hook strings', () async {
      final llm = _FakeLlm(
        response: '["Ask how the move went","Check in on the job hunt"]',
      );
      final svc = OutreachDraftService(llm);
      final out = await svc.suggestHooks(
        recentInteractions: [_interaction(summary: 'Coffee')],
      );
      expect(out, ['Ask how the move went', 'Check in on the job hunt']);
    });

    test('strips list-marker prefixes some models add', () async {
      final llm = _FakeLlm(
        response: '["- Ask how the move went","* Follow up on the job"]',
      );
      final svc = OutreachDraftService(llm);
      final out = await svc.suggestHooks(
        recentInteractions: [_interaction(summary: 'x')],
      );
      expect(out, ['Ask how the move went', 'Follow up on the job']);
    });

    test('deduplicates case-insensitively', () async {
      final llm = _FakeLlm(
        response: '["Ask about the move","ASK ABOUT THE MOVE"]',
      );
      final svc = OutreachDraftService(llm);
      final out = await svc.suggestHooks(
        recentInteractions: [_interaction(summary: 'x')],
      );
      expect(out.length, 1);
    });

    test('caps at 4 hooks', () async {
      final llm = _FakeLlm(
        response: '["a","b","c","d","e","f"]',
      );
      final svc = OutreachDraftService(llm);
      final out = await svc.suggestHooks(
        recentInteractions: [_interaction(summary: 'x')],
      );
      expect(out.length, 4);
    });

    test('returns empty list on malformed JSON without throwing', () async {
      final llm = _FakeLlm(response: 'sorry I cannot do that');
      final svc = OutreachDraftService(llm);
      final out = await svc.suggestHooks(
        recentInteractions: [_interaction(summary: 'x')],
      );
      expect(out, isEmpty);
    });

    test('only sends pending, non-deleted prayer requests to the model',
        () async {
      final llm = _FakeLlm(response: '["ok"]');
      final svc = OutreachDraftService(llm);
      await svc.suggestHooks(
        recentInteractions: [_interaction(summary: 'x')],
        activePrayerRequests: [
          _prayer(description: 'KEEP_PRAYER'),
          _prayer(
            description: 'ANSWERED_PRAYER',
            status: PrayerRequestStatus.answered,
          ),
          _prayer(
            description: 'DELETED_PRAYER',
            deletedAt: DateTime(2026, 4, 1),
          ),
        ],
      );
      final prompt = llm.lastPrompt!;
      expect(prompt, contains('KEEP_PRAYER'));
      expect(prompt, isNot(contains('ANSWERED_PRAYER')));
      expect(prompt, isNot(contains('DELETED_PRAYER')));
    });

    test('caps interactions at maxInteractions, newest first', () async {
      final llm = _FakeLlm(response: '["ok"]');
      final svc = OutreachDraftService(llm);
      final items = List.generate(
        12,
        (i) => _interaction(
          summary: 'Entry $i',
          occurredAt: DateTime(2026, 1, 1).add(Duration(days: i)),
        ),
      );
      await svc.suggestHooks(recentInteractions: items);
      final prompt = llm.lastPrompt!;
      expect(prompt, contains('Entry 11'));
      expect(prompt, contains('Entry 7'));
      expect(prompt, isNot(contains('Entry 6')));
    });

    test('does not include participant ids in the prompt', () async {
      final llm = _FakeLlm(response: '["ok"]');
      final svc = OutreachDraftService(llm);
      await svc.suggestHooks(
        recentInteractions: [
          Interaction(
            summary: 'Met up',
            medium: 'in_person',
            occurredAt: DateTime(2026, 5, 1),
            participantIds: const ['leak-me'],
          ),
        ],
        activePrayerRequests: [_prayer(description: 'Pray')],
      );
      expect(llm.lastPrompt, isNot(contains('leak-me')));
    });
  });
}
