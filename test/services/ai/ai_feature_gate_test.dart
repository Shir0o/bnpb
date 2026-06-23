import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/services/ai/ai_feature_gate.dart';

void main() {
  group('AiFeatureGate - suggestions on save setting', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to false when no value is stored', () async {
      final gate = AiFeatureGate();
      expect(await gate.isShowSuggestionsOnSaveEnabled(), isFalse);
    });

    test('reads stored value correctly', () async {
      SharedPreferences.setMockInitialValues({
        'ai.features.show_suggestions_on_save': false,
      });
      final gate = AiFeatureGate();
      expect(await gate.isShowSuggestionsOnSaveEnabled(), isFalse);
    });

    test('writes value correctly', () async {
      final gate = AiFeatureGate();
      await gate.setShowSuggestionsOnSaveEnabled(false);
      expect(await gate.isShowSuggestionsOnSaveEnabled(), isFalse);

      await gate.setShowSuggestionsOnSaveEnabled(true);
      expect(await gate.isShowSuggestionsOnSaveEnabled(), isTrue);
    });
  });
}
