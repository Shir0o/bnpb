/// Structured reference to a scripture passage. Carries enough information
/// for the Ready-to-log card to render the current ref and to advance to
/// the next ref (see [advance]).
class ScriptureRef {
  /// Canonical book code, e.g. `Psa`, `Gen`, `Matt`, `1Cor`.
  final String book;

  /// First chapter (or chapter of a verse-style ref).
  final int start;

  /// Last chapter. For single-chapter refs, equals [start].
  final int end;

  /// Optional verse number for verse-style refs like `Gen 1:2`.
  /// When set, [start] and [end] represent the verse range.
  final int? verseStart;
  final int? verseEnd;

  const ScriptureRef({
    required this.book,
    required this.start,
    required this.end,
    this.verseStart,
    this.verseEnd,
  });

  bool get _hasVerses => verseStart != null && verseEnd != null;

  /// "Psa. 117–118", "Ch. 6", "Gen. 1:2".
  String get display {
    final b = _canonicalBook(book);
    if (_hasVerses) {
      final vs = verseStart!;
      final ve = verseEnd!;
      if (vs == ve) return '$b. $start:$vs';
      return '$b. $start:$vs–$ve';
    }
    if (start == end) {
      return '$b. $start';
    }
    return '$b. $start–$end';
  }

  /// Next sequential ref of the same shape. For chapter ranges the size of
  /// the span is preserved so a 2-chapter range advances to a 2-chapter
  /// range (Psa 115–116 → Psa 117–118).
  ScriptureRef advance() {
    if (_hasVerses) {
      final span = verseEnd! - verseStart!;
      return ScriptureRef(
        book: book,
        start: start,
        end: end,
        verseStart: verseEnd! + 1,
        verseEnd: verseEnd! + 1 + span,
      );
    }
    final span = end - start;
    return ScriptureRef(
      book: book,
      start: end + 1,
      end: end + 1 + span,
    );
  }

  static String _canonicalBook(String raw) {
    final b = raw.replaceAll('.', '').replaceAll(' ', '');
    const map = {
      'Psa': 'Psa',
      'Psalm': 'Psa',
      'Psalms': 'Psa',
      'Gen': 'Gen',
      'Matt': 'Matt',
      '1Cor': '1 Cor',
    };
    return map[b] ?? raw;
  }

  /// Tries to extract and advance a scripture reference from [text] using
  /// only regex (no AI). Returns null if [text] is empty or no recognized
  /// pattern is present.
  ///
  /// Recognized shapes:
  ///   - PSA / Psa / Psalms + range "115-116" or "115–116"
  ///   - PSA / Psa / Psalms + single chapter "117"
  ///   - Book abbreviations (Gen, Matt, 1 Cor, 1 Cor.) + "5"
  ///   - "Gen 1:1" style (book + chapter + verse) — advances verse only
  ///   - Ch / Chapter + number
  static ScriptureRef? tryAdvance(String? text) {
    if (text == null || text.isEmpty) return null;

    final patterns = <RegExp, ScriptureRef? Function(RegExpMatch)>{
      // PSA / Psa / Psalms + range "115-116" (en-dash or hyphen).
      _psaRange: (m) {
        final a = int.tryParse(m.group(1)!) ?? 0;
        final b = int.tryParse(m.group(2)!) ?? 0;
        if (a <= 0 || b < a) return null;
        return ScriptureRef(book: 'Psa', start: a, end: b).advance();
      },
      // PSA / Psa / Psalms + single chapter.
      _psaSingle: (m) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n <= 0) return null;
        return ScriptureRef(book: 'Psa', start: n, end: n).advance();
      },
      // Book + chapter:verse (e.g. "Gen 1:1").
      _bookChapterVerse: (m) {
        final book = m.group(1)!;
        final ch = int.tryParse(m.group(2)!) ?? 0;
        final v1 = int.tryParse(m.group(3)!) ?? 0;
        final v2 = m.group(4) != null ? (int.tryParse(m.group(4)!) ?? v1) : v1;
        if (ch <= 0 || v1 <= 0 || v2 < v1) return null;
        return ScriptureRef(
          book: book,
          start: ch,
          end: ch,
          verseStart: v1,
          verseEnd: v2,
        ).advance();
      },
      // Book + chapter only (e.g. "Matt 5", "Gen 3", "1 Cor 13").
      _bookChapter: (m) {
        final book = m.group(1)!;
        final ch = int.tryParse(m.group(2)!) ?? 0;
        if (ch <= 0) return null;
        return ScriptureRef(book: book, start: ch, end: ch).advance();
      },
      // Ch. / Chapter + number.
      _ch: (m) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n <= 0) return null;
        return ScriptureRef(book: 'Ch', start: n, end: n).advance();
      },
    };

    for (final entry in patterns.entries) {
      final m = entry.key.firstMatch(text);
      if (m != null) {
        final ref = entry.value(m);
        if (ref != null) return ref;
      }
    }
    return null;
  }

  static final RegExp _psaRange = RegExp(
    r'(?:PSA|Psa\.?|Psalms?)[^0-9]*(\d+)\s*[–-]\s*(\d+)',
    caseSensitive: false,
  );

  static final RegExp _psaSingle = RegExp(
    r'(?:PSA|Psa\.?|Psalms?)[^0-9]*(\d+)(?!\s*[–\-:])',
    caseSensitive: false,
  );

  static final RegExp _bookChapterVerse = RegExp(
    r'\b(Gen|Matt|1\s*Cor\.?|Mark|Luke|John|Acts|Rom)\s+(\d+):(\d+)(?:[–\-](\d+))?',
    caseSensitive: false,
  );

  static final RegExp _bookChapter = RegExp(
    r'\b(Gen|Matt|1\s*Cor\.?|Mark|Luke|John|Acts|Rom)\s+(\d+)(?!\s*[–\-:])',
    caseSensitive: false,
  );

  static final RegExp _ch = RegExp(
    r'(?:Ch\.?|Chapter)\s*(\d+)',
    caseSensitive: false,
  );
}
