import 'package:bnpb/services/ai/scripture_ref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScriptureRef.tryAdvance (regex-only path)', () {
    test('returns null for null input', () {
      expect(ScriptureRef.tryAdvance(null), isNull);
    });

    test('returns null for empty input', () {
      expect(ScriptureRef.tryAdvance(''), isNull);
    });

    test('advances PSA range with en-dash (existing behavior preserved)', () {
      expect(ScriptureRef.tryAdvance('PSA 115–116')?.display, 'Psa. 117–118');
    });

    test('advances PSA range with hyphen-minus', () {
      expect(ScriptureRef.tryAdvance('Psa. 112-113')?.display, 'Psa. 114–115');
    });

    test('advances Ch. with period', () {
      expect(ScriptureRef.tryAdvance('Ch. 5')?.display, 'Ch. 6');
    });

    test('advances Chapter spelled out', () {
      expect(ScriptureRef.tryAdvance('Chapter 3')?.display, 'Ch. 4');
    });

    test('advances lowercase ch', () {
      expect(ScriptureRef.tryAdvance('ch. 7')?.display, 'Ch. 8');
    });

    test('advances single PSA chapter (no range) — NEW', () {
      expect(ScriptureRef.tryAdvance('Psa 117')?.display, 'Psa. 118');
    });

    test('advances Psalms single chapter — NEW', () {
      expect(ScriptureRef.tryAdvance('Psalm 117')?.display, 'Psa. 118');
    });

    test('advances verse-style Gen 1:1 — NEW', () {
      expect(ScriptureRef.tryAdvance('Gen 1:1')?.display, 'Gen. 1:2');
    });

    test('advances book abbreviation Matt 5 — NEW', () {
      expect(ScriptureRef.tryAdvance('Matt 5')?.display, 'Matt. 6');
    });

    test('advances 1 Cor chapter — NEW', () {
      expect(ScriptureRef.tryAdvance('1 Cor 13')?.display, '1 Cor. 14');
    });

    test('returns null for unrecognized free-form text', () {
      expect(ScriptureRef.tryAdvance('had coffee with tim'), isNull);
    });

    test('returns null for word-form chapter ("Psalm one-seventeen")', () {
      // Word-form is intentionally out of scope for regex; covered by AI slice.
      expect(ScriptureRef.tryAdvance('Psalm one-seventeen'), isNull);
    });
  });
}
