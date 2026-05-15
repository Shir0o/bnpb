import '../models/contact.dart';

/// A group of contacts in an import that are suspected duplicates of each
/// other. The first member is treated as the primary when merging.
class DuplicateGroup {
  DuplicateGroup({required this.members, required this.reason});

  final List<Contact> members;
  final String reason;
}

/// Detects suspected intra-import duplicates among a list of incoming
/// contacts, using cheap deterministic heuristics (no LLM, no embeddings).
///
/// Matching tiers (any one triggers a pair):
///   1. Shared normalized phone (digits only, last 10 digits compared).
///   2. Shared normalized email (lowercased, trimmed).
///   3. Last-name trigram similarity >= 0.6 AND first-name trigram
///      similarity >= 0.6.
///   4. Last-name trigram similarity >= 0.6 AND one contact's nickname
///      trigram-matches the other's first name >= 0.6 (nickname expansion,
///      e.g. "Bob" -> "Robert").
///
/// Sibling false-positive avoidance: tiers 3/4 both require last-name AND
/// first-name evidence, so "Alice Smith" vs "Bob Smith" does not match.
///
/// Performance: phone/email matches are found via O(N) hash bucketing, and
/// the trigram-name comparison uses a last-name trigram inverted index so
/// only contacts sharing at least one last-name trigram are pairwise scored
/// — avoiding the naive O(N^2) sweep.
class ImportDuplicateDetector {
  static const double _trigramThreshold = 0.6;

  List<DuplicateGroup> findDuplicateGroups(List<Contact> contacts) {
    if (contacts.length < 2) return const [];

    final fingerprints = contacts.map(_ContactFingerprint.from).toList();
    final uf = _UnionFind(contacts.length);
    final reasons = <int, String>{};

    void link(int a, int b, String reason) {
      final ra = uf.find(a);
      final rb = uf.find(b);
      if (ra == rb) return;
      uf.union(a, b);
      final root = uf.find(a);
      reasons[root] = reasons[ra] ?? reasons[rb] ?? reason;
    }

    void scorePair(int i, int j) {
      final a = fingerprints[i];
      final b = fingerprints[j];

      final lastSim = _jaccard(a.lastNameTrigrams, b.lastNameTrigrams);
      if (lastSim < _trigramThreshold) return;

      final firstSim = _jaccard(a.firstNameTrigrams, b.firstNameTrigrams);
      if (firstSim >= _trigramThreshold) {
        link(i, j, 'Similar name');
        return;
      }

      final nickToFirst = _jaccard(a.nicknameTrigrams, b.firstNameTrigrams);
      final firstToNick = _jaccard(a.firstNameTrigrams, b.nicknameTrigrams);
      if (nickToFirst >= _trigramThreshold ||
          firstToNick >= _trigramThreshold) {
        link(i, j, 'Nickname match');
      }
    }

    // Pass 1: link via exact phone / email buckets in O(N).
    final phoneBuckets = <String, List<int>>{};
    final emailBuckets = <String, List<int>>{};
    for (var i = 0; i < fingerprints.length; i++) {
      final fp = fingerprints[i];
      if (fp.phone.isNotEmpty) {
        phoneBuckets.putIfAbsent(fp.phone, () => []).add(i);
      }
      if (fp.email.isNotEmpty) {
        emailBuckets.putIfAbsent(fp.email, () => []).add(i);
      }
    }
    for (final bucket in phoneBuckets.values) {
      for (var k = 1; k < bucket.length; k++) {
        link(bucket[0], bucket[k], 'Shared phone number');
      }
    }
    for (final bucket in emailBuckets.values) {
      for (var k = 1; k < bucket.length; k++) {
        link(bucket[0], bucket[k], 'Shared email');
      }
    }

    // Pass 2: trigram-blocked name comparison. A pair only enters scoring
    // if they share at least one last-name trigram (necessary condition for
    // last-name Jaccard >= 0.6 / threshold > 0).
    final lastNameIndex = <String, List<int>>{};
    for (var i = 0; i < fingerprints.length; i++) {
      for (final gram in fingerprints[i].lastNameTrigrams) {
        lastNameIndex.putIfAbsent(gram, () => []).add(i);
      }
    }
    final scored = <int>{};
    for (var i = 0; i < fingerprints.length; i++) {
      scored.clear();
      for (final gram in fingerprints[i].lastNameTrigrams) {
        for (final j in lastNameIndex[gram]!) {
          if (j <= i || scored.contains(j)) continue;
          scored.add(j);
          scorePair(i, j);
        }
      }
    }

    final groups = <int, List<int>>{};
    for (var i = 0; i < contacts.length; i++) {
      final root = uf.find(i);
      if (uf.sizeOf(root) < 2) continue;
      groups.putIfAbsent(root, () => []).add(i);
    }

    return groups.entries
        .map(
          (entry) => DuplicateGroup(
            members: [for (final idx in entry.value) contacts[idx]],
            reason: reasons[entry.key] ?? 'Similar contact',
          ),
        )
        .toList();
  }
}

class _ContactFingerprint {
  _ContactFingerprint({
    required this.phone,
    required this.email,
    required this.firstNameTrigrams,
    required this.lastNameTrigrams,
    required this.nicknameTrigrams,
  });

  final String phone;
  final String email;
  final Set<String> firstNameTrigrams;
  final Set<String> lastNameTrigrams;
  final Set<String> nicknameTrigrams;

  static _ContactFingerprint from(Contact c) {
    return _ContactFingerprint(
      phone: _normalizePhone(c.phone),
      email: _normalizeEmail(c.email),
      firstNameTrigrams: _trigrams(_normalize(c.firstName)),
      lastNameTrigrams: _trigrams(_normalize(c.lastName ?? '')),
      nicknameTrigrams: _trigrams(_normalize(c.nickname ?? '')),
    );
  }
}

class _UnionFind {
  _UnionFind(int n)
      : _parent = List<int>.generate(n, (i) => i),
        _size = List<int>.filled(n, 1);

  final List<int> _parent;
  final List<int> _size;

  int find(int x) {
    while (_parent[x] != x) {
      _parent[x] = _parent[_parent[x]];
      x = _parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    if (_size[ra] < _size[rb]) {
      _parent[ra] = rb;
      _size[rb] += _size[ra];
    } else {
      _parent[rb] = ra;
      _size[ra] += _size[rb];
    }
  }

  int sizeOf(int root) => _size[root];
}

final RegExp _nonAlnum = RegExp(r'[^a-z0-9]+');
final RegExp _nonDigit = RegExp(r'\D');

String _normalize(String value) =>
    value.toLowerCase().replaceAll(_nonAlnum, ' ').trim();

String _normalizePhone(String? value) {
  if (value == null) return '';
  final digits = value.replaceAll(_nonDigit, '');
  if (digits.isEmpty) return '';
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

String _normalizeEmail(String? value) {
  if (value == null) return '';
  return value.trim().toLowerCase();
}

Set<String> _trigrams(String text) {
  if (text.isEmpty) return const {};
  if (text.length <= 3) return {text};
  final padded = '  $text  ';
  final grams = <String>{};
  for (var i = 0; i < padded.length - 2; i++) {
    grams.add(padded.substring(i, i + 3));
  }
  return grams;
}

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final intersection = a.intersection(b).length;
  final union = a.length + b.length - intersection;
  if (union == 0) return 0;
  return intersection / union;
}
