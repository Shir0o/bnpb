/// Static canonical metadata for the Protestant Bible.
///
/// [ScriptureRef] uses this to parse book names and to advance across book
/// boundaries when a reading plan spans more than one book.
class BibleBook {
  const BibleBook(this.code, this.chapters, this.aliases);

  /// Canonical short code used by [ScriptureRef], e.g. `Gen`, `Psa`, `1Cor`.
  final String code;

  /// Number of chapters in the book.
  final int chapters;

  /// Normalized aliases accepted by the parser.
  final List<String> aliases;
}

const List<BibleBook> bibleBooks = [
  BibleBook('Gen', 50, ['gen', 'genesis']),
  BibleBook('Exod', 40, ['ex', 'exo', 'exod', 'exodus']),
  BibleBook('Lev', 27, ['lev', 'leviticus']),
  BibleBook('Num', 36, ['num', 'numbers']),
  BibleBook('Deut', 34, ['deut', 'deuteronomy']),
  BibleBook('Josh', 24, ['josh', 'joshua']),
  BibleBook('Judg', 21, ['judg', 'judges']),
  BibleBook('Ruth', 4, ['ruth']),
  BibleBook('1Sam', 31, ['1sam', '1 samuel']),
  BibleBook('2Sam', 24, ['2sam', '2 samuel']),
  BibleBook('1Kgs', 22, ['1kgs', '1kings', '1 kings']),
  BibleBook('2Kgs', 25, ['2kgs', '2kings', '2 kings']),
  BibleBook('1Chr', 29, ['1chr', '1chronicles', '1 chronicles']),
  BibleBook('2Chr', 36, ['2chr', '2chronicles', '2 chronicles']),
  BibleBook('Ezra', 10, ['ezra']),
  BibleBook('Neh', 13, ['neh', 'nehemiah']),
  BibleBook('Esth', 10, ['esth', 'esther']),
  BibleBook('Job', 42, ['job']),
  BibleBook('Psa', 150, ['ps', 'psa', 'psalm', 'psalms']),
  BibleBook('Prov', 31, ['prov', 'proverbs']),
  BibleBook('Eccl', 12, ['eccl', 'ecclesiastes']),
  BibleBook('Song', 8, [
    'song',
    'songofsongs',
    'songofsolomon',
    'sos',
  ]),
  BibleBook('Isa', 66, ['isa', 'isaiah']),
  BibleBook('Jer', 52, ['jer', 'jeremiah']),
  BibleBook('Lam', 5, ['lam', 'lamentations']),
  BibleBook('Ezek', 48, ['ezek', 'ezekiel']),
  BibleBook('Dan', 12, ['dan', 'daniel']),
  BibleBook('Hos', 14, ['hos', 'hosea']),
  BibleBook('Joel', 3, ['joel']),
  BibleBook('Amos', 9, ['amos']),
  BibleBook('Obad', 1, ['obad', 'obadiah']),
  BibleBook('Jonah', 4, ['jonah']),
  BibleBook('Mic', 7, ['mic', 'micah']),
  BibleBook('Nah', 3, ['nah', 'nahum']),
  BibleBook('Hab', 3, ['hab', 'habakkuk']),
  BibleBook('Zeph', 3, ['zeph', 'zephaniah']),
  BibleBook('Hag', 2, ['hag', 'haggai']),
  BibleBook('Zech', 14, ['zech', 'zechariah']),
  BibleBook('Mal', 4, ['mal', 'malachi']),
  BibleBook('Matt', 28, ['matt', 'matthew']),
  BibleBook('Mark', 16, ['mark', 'mk']),
  BibleBook('Luke', 24, ['luke', 'lk']),
  BibleBook('John', 21, ['john', 'jn']),
  BibleBook('Acts', 28, ['acts', 'act']),
  BibleBook('Rom', 16, ['rom', 'romans']),
  BibleBook('1Cor', 16, ['1cor', '1corinthians', '1 corinthians']),
  BibleBook('2Cor', 13, ['2cor', '2corinthians', '2 corinthians']),
  BibleBook('Gal', 6, ['gal', 'galatians']),
  BibleBook('Eph', 6, ['eph', 'ephesians']),
  BibleBook('Phil', 4, ['phil', 'philippians']),
  BibleBook('Col', 4, ['col', 'colossians']),
  BibleBook('1Thess', 5, ['1thess', '1thessalonians', '1 thessalonians']),
  BibleBook('2Thess', 3, ['2thess', '2thessalonians', '2 thessalonians']),
  BibleBook('1Tim', 6, ['1tim', '1timothy', '1 timothy']),
  BibleBook('2Tim', 4, ['2tim', '2timothy', '2 timothy']),
  BibleBook('Titus', 3, ['titus']),
  BibleBook('Phlm', 1, ['phlm', 'philemon']),
  BibleBook('Heb', 13, ['heb', 'hebrews']),
  BibleBook('Jas', 5, ['jas', 'james']),
  BibleBook('1Pet', 5, ['1pet', '1peter', '1 peter']),
  BibleBook('2Pet', 3, ['2pet', '2peter', '2 peter']),
  BibleBook('1John', 5, ['1john', '1 john']),
  BibleBook('2John', 1, ['2john', '2 john']),
  BibleBook('3John', 1, ['3john', '3 john']),
  BibleBook('Jude', 1, ['jude']),
  BibleBook('Rev', 22, ['rev', 'revelation', 'revelations']),
];

final Map<String, BibleBook> _booksByCode = {
  for (final book in bibleBooks) normalizeBibleToken(book.code): book,
};

final Map<String, BibleBook> _booksByAlias = {
  for (final book in bibleBooks)
    for (final alias in book.aliases) normalizeBibleToken(alias): book,
};

/// Normalizes a book token for matching: lower-case, remove periods and
/// spaces, and strip a leading numbering space (e.g. `1 Cor` -> `1cor`).
String normalizeBibleToken(String value) {
  return value
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
}

/// Returns canonical metadata for [raw], or null when the token is not a
/// recognized Bible book.
BibleBook? lookupBibleBook(String raw) {
  final key = normalizeBibleToken(raw);
  if (key.isEmpty) return null;
  return _booksByAlias[key] ?? _booksByCode[key];
}

/// Canonical index of [book] in Bible order, or null when unknown.
int? bibleBookIndex(String book) {
  final canonical = lookupBibleBook(book);
  if (canonical == null) return null;
  return bibleBooks.indexOf(canonical);
}

/// Human-readable canonical code for [raw], preserving unrecognized tokens.
String canonicalBookCode(String raw) {
  final code = lookupBibleBook(raw)?.code ?? raw.replaceAll('.', '').trim();
  if (code.length > 2 && RegExp(r'^[1-3]').hasMatch(code)) {
    return '${code[0]} ${code.substring(1)}';
  }
  return code;
}
