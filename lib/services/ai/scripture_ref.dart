import 'scripture_canon.dart';

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

  /// Number of chapters covered by this reference.
  int get chaptersRead => end - start + 1;

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

  ScripturePassage? nextPassage({required int chapters}) {
    if (chapters <= 0 || _hasVerses) return null;
    final currentBook = lookupBibleBook(book);
    if (currentBook == null) return null;
    var bookIndex = bibleBooks.indexOf(currentBook);
    var chapterStart = end + 1;
    var remaining = chapters;
    final refs = <ScriptureRef>[];

    while (remaining > 0 && bookIndex < bibleBooks.length) {
      final bookInfo = bibleBooks[bookIndex];
      if (chapterStart > bookInfo.chapters) {
        bookIndex++;
        chapterStart = 1;
        continue;
      }
      final available = bookInfo.chapters - chapterStart + 1;
      final take = remaining < available ? remaining : available;
      refs.add(ScriptureRef(
        book: bookInfo.code,
        start: chapterStart,
        end: chapterStart + take - 1,
      ));
      remaining -= take;
      bookIndex++;
      chapterStart = 1;
    }
    if (remaining > 0 || refs.isEmpty) return null;
    return ScripturePassage(refs);
  }

  static String _canonicalBook(String raw) => canonicalBookCode(raw);

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
  /// Parses the first recognizable scripture reference in [text].
  static ScriptureRef? tryParse(String? text) {
    final refs = tryParseAll(text);
    return refs.isEmpty ? null : refs.first;
  }

  /// Parses the last reference in canonical reading order from [text].
  static ScriptureRef? tryParseLast(String? text) {
    final refs = tryParseAll(text);
    if (refs.isEmpty) return null;
    refs.sort(_compareCanonical);
    return refs.last;
  }

  static ScriptureRef? tryAdvance(String? text) {
    return tryParseLast(text)?.advance();
  }

  static List<ScriptureRef> tryParseAll(String? text) {
    if (text == null || text.isEmpty) return const [];
    final safeText = text.replaceAll('\u2013', '-');
    final refs = <ScriptureRef>[];
    for (final match in _referencePattern.allMatches(safeText)) {
      final book = match.group(1);
      final chapterRaw = match.group(2);
      if (book == null || chapterRaw == null) continue;
      final bookInfo = lookupBibleBook(book);
      if (bookInfo == null) continue;
      final chapter = int.tryParse(chapterRaw);
      if (chapter == null || chapter <= 0) continue;
      final verseStartRaw = match.group(3);
      final verseEndRaw = match.group(4);
      final chapterEndRaw = match.group(5);
      if (verseStartRaw != null) {
        final verseStart = int.tryParse(verseStartRaw);
        final verseEnd =
            verseEndRaw == null ? verseStart : int.tryParse(verseEndRaw);
        if (verseStart == null || verseEnd == null || verseStart <= 0) {
          continue;
        }
        if (verseEnd < verseStart) continue;
        refs.add(ScriptureRef(
          book: bookInfo.code,
          start: chapter,
          end: chapter,
          verseStart: verseStart,
          verseEnd: verseEnd,
        ));
        continue;
      }
      final chapterEnd =
          chapterEndRaw == null ? chapter : int.tryParse(chapterEndRaw);
      if (chapterEnd == null || chapterEnd < chapter) continue;
      refs.add(ScriptureRef(
        book: bookInfo.code,
        start: chapter,
        end: chapterEnd,
      ));
    }

    if (refs.isEmpty) {
      final chapterMatch = _chapterOnlyPattern.firstMatch(safeText);
      if (chapterMatch != null) {
        final chapter = int.tryParse(chapterMatch.group(1) ?? '');
        if (chapter != null && chapter > 0) {
          refs.add(ScriptureRef(book: 'Ch', start: chapter, end: chapter));
        }
      }
    }
    return refs;
  }

  static int _compareCanonical(ScriptureRef a, ScriptureRef b) {
    final aIndex = bibleBookIndex(a.book) ?? 9999;
    final bIndex = bibleBookIndex(b.book) ?? 9999;
    if (aIndex != bIndex) return aIndex.compareTo(bIndex);
    if (a.start != b.start) return a.start.compareTo(b.start);
    return a.end.compareTo(b.end);
  }

  static final RegExp _referencePattern = RegExp(
    r'((?:[1-3]\s*)?[A-Za-z]{2,}\.?)\s+(\d+)'
    r'(?:\s*:\s*(\d+)(?:\s*-\s*(\d+))?)?'
    r'(?:\s*-\s*(\d+))?',
    caseSensitive: false,
  );

  static final RegExp _chapterOnlyPattern = RegExp(
    r'(?:Ch\.?|Chapter)\s*(\d+)',
    caseSensitive: false,
  );
}

/// A sequence of one or more [ScriptureRef]s that together form one reading
/// session. A cross-book session is rendered as `Psa. 150; Prov. 1`.
class ScripturePassage {
  const ScripturePassage(this.refs);

  final List<ScriptureRef> refs;

  bool get isEmpty => refs.isEmpty;

  String get display => refs.map((ref) => ref.display).join('; ');

  ScripturePassage? advanceByChapters({required int chapters}) {
    if (refs.isEmpty || chapters <= 0) return null;
    return refs.last.nextPassage(chapters: chapters);
  }
}
