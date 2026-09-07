import 'package:bnpb/services/ai/ai_feature_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AiFeatureGate - scripture ref advancement setting', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to false when no value is stored', () async {
      final gate = AiFeatureGate();
      expect(await gate.isScriptureRefAdvancementEnabled(), isFalse);
    });

    test('reads stored value correctly', () async {
      SharedPreferences.setMockInitialValues({
        'ai.features.scripture_ref_advancement': true,
      });
      final gate = AiFeatureGate();
      expect(await gate.isScriptureRefAdvancementEnabled(), isTrue);
    });

    test('writes value correctly (round-trip)', () async {
      final gate = AiFeatureGate();
      await gate.setScriptureRefAdvancementEnabled(true);
      expect(await gate.isScriptureRefAdvancementEnabled(), isTrue);

      await gate.setScriptureRefAdvancementEnabled(false);
      expect(await gate.isScriptureRefAdvancementEnabled(), isFalse);
    });

    test('independent of showSuggestionsOnSave', () async {
      SharedPreferences.setMockInitialValues({
        'ai.features.show_suggestions_on_save': true,
      });
      final gate = AiFeatureGate();
      expect(await gate.isShowSuggestionsOnSaveEnabled(), isTrue);
      expect(await gate.isScriptureRefAdvancementEnabled(), isFalse);
    });
  });
}
