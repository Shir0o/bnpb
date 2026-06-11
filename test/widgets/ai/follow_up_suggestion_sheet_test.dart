import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/ai/ai_services.dart';
import 'package:bnpb/services/ai/ai_feature_gate.dart';
import 'package:bnpb/services/ai/local_llm_service.dart';
import 'package:bnpb/widgets/ai/follow_up_suggestion_sheet.dart';

class FakeAiFeatureGate extends Fake implements AiFeatureGate {
  FakeAiFeatureGate({
    required this.enabled,
    required this.suggestionsEnabled,
  });
  final bool enabled;
  final bool suggestionsEnabled;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> isShowSuggestionsOnSaveEnabled() async => suggestionsEnabled;
}

class FakeLocalLlmService extends Fake implements LocalLlmService {
  @override
  bool get isReady => true;
}

void main() {
  group('FollowUpSuggestionSheet settings integration', () {
    final contact = Contact(id: 'c1', firstName: 'John', lastName: 'Doe');
    final interaction = Interaction(
      id: 1,
      occurredAt: DateTime.now(),
      summary: 'Discussed project plans',
      medium: 'in_person',
      participantIds: ['c1'],
    );

    testWidgets(
        'does not show modal bottom sheet when isShowSuggestionsOnSaveEnabled is false',
        (tester) async {
      final fakeGate =
          FakeAiFeatureGate(enabled: true, suggestionsEnabled: false);
      final fakeLlm = FakeLocalLlmService();
      AiServices().debugOverride(gate: fakeGate, llm: fakeLlm);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await FollowUpSuggestionSheet.maybeShow(
                      context,
                      contact: contact,
                      interaction: interaction,
                      onInteractionUpdated: (_) {},
                    );
                  },
                  child: const Text('Show Sheet'),
                );
              },
            ),
          ),
        ),
      );

      // Tap the button to trigger maybeShow
      await tester.tap(find.text('Show Sheet'));
      await tester.pumpAndSettle();

      // The sheet should not be visible
      expect(find.text('Suggested follow-ups'), findsNothing);
    });

    testWidgets(
        'shows modal bottom sheet when isShowSuggestionsOnSaveEnabled is true',
        (tester) async {
      final fakeGate =
          FakeAiFeatureGate(enabled: true, suggestionsEnabled: true);
      final fakeLlm = FakeLocalLlmService();
      AiServices().debugOverride(gate: fakeGate, llm: fakeLlm);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await FollowUpSuggestionSheet.maybeShow(
                      context,
                      contact: contact,
                      interaction: interaction,
                      onInteractionUpdated: (_) {},
                    );
                  },
                  child: const Text('Show Sheet'),
                );
              },
            ),
          ),
        ),
      );

      // Tap the button to trigger maybeShow
      await tester.tap(find.text('Show Sheet'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(seconds: 1)); // finish animation

      // The sheet should be visible now
      expect(find.text('Suggested follow-ups'), findsOneWidget);
    });

    testWidgets(
        'shows modal bottom sheet and falls back to heuristics when AI is disabled (enabled: false)',
        (tester) async {
      final fakeGate =
          FakeAiFeatureGate(enabled: false, suggestionsEnabled: true);
      final fakeLlm = FakeLocalLlmService();
      AiServices().debugOverride(gate: fakeGate, llm: fakeLlm);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await FollowUpSuggestionSheet.maybeShow(
                      context,
                      contact: contact,
                      interaction: interaction,
                      onInteractionUpdated: (_) {},
                    );
                  },
                  child: const Text('Show Sheet'),
                );
              },
            ),
          ),
        ),
      );

      // Tap the button to trigger maybeShow
      await tester.tap(find.text('Show Sheet'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(seconds: 1)); // finish animation

      // The sheet should be visible and showing suggestions
      expect(find.text('Suggested follow-ups'), findsOneWidget);
    });
  });
}
