import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/ai/ai_feature_gate.dart';
import 'package:bnpb/services/ai/ai_services.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:bnpb/services/ai/time_tracker_ai_resolver.dart';

class _FakeLlmService implements LocalLlmService {
  String response = '[]';
  Duration delay = Duration.zero;

  @override
  bool get isReady => true;

  @override
  Future<void> load(String modelPath) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return response;
  }
}

class _FakeFeatureGate extends AiFeatureGate {
  final bool enabled;
  _FakeFeatureGate({this.enabled = true});

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<AiBackend> backend() async => AiBackend.local;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeTrackerAiResolver', () {
    late _FakeLlmService fakeLlm;
    late AiServices aiServices;

    final contacts = [
      Contact(id: 'c1', firstName: 'Abel', lastName: 'Smith'),
      Contact(id: 'c2', firstName: 'Benji', lastName: 'Lee'),
    ];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeLlm = _FakeLlmService();
      aiServices = AiServices();
      aiServices.debugOverride(
        llm: fakeLlm,
        gate: _FakeFeatureGate(enabled: true),
      );
    });

    test('returns matching contact ids when LLM responds with JSON array',
        () async {
      fakeLlm.response = '["c1"]';
      final resolver = TimeTrackerAiResolver(aiServices: aiServices);

      final candidate = CandidateInteraction(
        fingerprint: 'fp1',
        occurredAt: DateTime.now(),
        durationMinutes: 30,
        activityName: 'Lunch',
        summary: 'Lunch',
        matchedContactIds: [],
        rawComment: 'lunch with Abel',
      );

      final matched = await resolver.resolveContactsForCandidate(
        candidate: candidate,
        contacts: contacts,
      );

      expect(matched, ['c1']);
    });

    test('returns empty when AI is disabled', () async {
      aiServices.debugOverride(
        llm: fakeLlm,
        gate: _FakeFeatureGate(enabled: false),
      );
      final resolver = TimeTrackerAiResolver(aiServices: aiServices);

      final candidate = CandidateInteraction(
        fingerprint: 'fp1',
        occurredAt: DateTime.now(),
        durationMinutes: 30,
        activityName: 'Lunch',
        summary: 'Lunch',
        matchedContactIds: [],
        rawComment: 'lunch with Abel',
      );

      final matched = await resolver.resolveContactsForCandidate(
        candidate: candidate,
        contacts: contacts,
      );

      expect(matched, isEmpty);
    });

    test('handles timeout gracefully without crashing', () async {
      fakeLlm.delay = const Duration(seconds: 20); // Exceeds 15s timeout
      final resolver = TimeTrackerAiResolver(aiServices: aiServices);

      final candidate = CandidateInteraction(
        fingerprint: 'fp1',
        occurredAt: DateTime.now(),
        durationMinutes: 30,
        activityName: 'Lunch',
        summary: 'Lunch',
        matchedContactIds: [],
        rawComment: 'lunch with Abel',
      );

      // Will timeout and safely return empty list
      final matched = await resolver.resolveContactsForCandidate(
        candidate: candidate,
        contacts: contacts,
      );

      expect(matched, isEmpty);
    });
  });
}
