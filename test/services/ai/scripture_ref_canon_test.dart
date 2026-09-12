import 'package:bnpb/services/ai/scripture_ref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScriptureRef canonical parsing', () {
    test('parses a current reference without advancing it', () {
      final ref = ScriptureRef.tryParse('Psa 117') as ScriptureRef;
      expect(ref.start, 117);
      expect(ref.end, 117);
    });

    test('parses the last reference from a cross-book payload', () {
      final ref =
          ScriptureRef.tryParseLast('Psa. 150; Prov. 1') as ScriptureRef;
      expect(ref.book, 'Prov');
      expect(ref.start, 1);
      expect(ref.end, 1);
    });

    test('continues into the next book when a two-chapter span crosses it', () {
      final current = ScriptureRef.tryParse('Psa 149') as ScriptureRef;
      final passage = current.nextPassage(chapters: 2) as ScripturePassage;
      expect(passage.display, 'Psa. 150; Prov. 1');
    });

    test('returns null when a span would pass the end of Revelation', () {
      final current = ScriptureRef.tryParse('Rev 22') as ScriptureRef;
      expect(current.nextPassage(chapters: 1), isNull);
    });
  });
}
